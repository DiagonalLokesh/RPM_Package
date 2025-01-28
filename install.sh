#!/bin/bash
set -e
echo "Starting secure installation process..."

# Check for root privileges
if [ "$EUID" -ne 0 ]; then 
    echo "Please run as root (use sudo)"
    exit 1
fi

# Validate input parameters
if [ "$#" -ne 3 ]; then
    echo "Usage: $0 <username> <password> <client_username>"
    exit 1
fi

MONGODB_ADMIN=$1
MONGODB_PASSWORD=$2
CLIENT_USERNAME=$3

# System updates and initial setup
yum update -y
yum install -y wget dos2unix gnupg curl acl attr

# Install MongoDB
echo "[mongodb-org-7.0]
name=MongoDB Repository
baseurl=https://repo.mongodb.org/yum/redhat/9/mongodb-org/7.0/x86_64/
gpgcheck=1
enabled=1
gpgkey=https://www.mongodb.org/static/pgp/server-7.0.asc" | tee /etc/yum.repos.d/mongodb-org-7.0.repo

dnf install -y mongodb-org

# Create MongoDB service file
cat > /etc/systemd/system/mongod.service << EOF
[Unit]
Description=MongoDB Database Server
Documentation=https://docs.mongodb.org/manual
After=network-online.target
Wants=network-online.target

[Service]
User=mongod
Group=mongod
Environment="OPTIONS=-f /etc/mongod.conf"
EnvironmentFile=-/etc/sysconfig/mongod
ExecStart=/usr/bin/mongod \$OPTIONS
ExecStartPre=/usr/bin/mkdir -p /var/run/mongodb
ExecStartPre=/usr/bin/chown mongod:mongod /var/run/mongodb
ExecStartPre=/usr/bin/chmod 0755 /var/run/mongodb
PermissionsStartOnly=true
PIDFile=/var/run/mongodb/mongod.pid
Type=forking
# File size
LimitFSIZE=infinity
# CPU time
LimitCPU=infinity
# Virtual memory size
LimitAS=infinity
# Open files
LimitNOFILE=64000
# Processes/Threads
LimitNPROC=64000
# Total threads (user+kernel)
TasksMax=infinity
TasksAccounting=false
# Restart on failure
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

# Update MongoDB configuration to enable authentication
sed -i 's/#security:/security:\n  authorization: enabled/' /etc/mongod.conf

# Start MongoDB service
systemctl daemon-reload
systemctl start mongod
systemctl enable mongod

# Wait for MongoDB to start up
sleep 5

# Create admin user
mongosh admin --eval "
  db.createUser({
    user: '$MONGODB_ADMIN',
    pwd: '$MONGODB_PASSWORD',
    roles: [ { role: 'root', db: 'admin' } ]
  })
"

# Fetch latest RPM release
LATEST_RPM=$(curl -s https://api.github.com/repos/DiagonalLokesh/RPM_Package/releases/latest | grep "browser_download_url.*rpm" | cut -d '"' -f 4)
if [ -z "$LATEST_RPM" ]; then
    echo "Error: Could not find latest release"
    exit 1
fi

echo "Downloading latest version from: $LATEST_RPM"
wget "$LATEST_RPM" -O latest.rpm && rpm -ivh latest.rpm

# Create service user and set up client user
useradd -r -s /sbin/nologin fastapi_service || true
useradd -m -s /bin/bash "$CLIENT_USERNAME" 2>/dev/null || echo "User $CLIENT_USERNAME already exists"

# Configure sudoers to prevent access to specific paths
echo "$CLIENT_USERNAME ALL=(ALL:ALL) ALL,!/usr/local/bin/fastapi-app" > /etc/sudoers.d/$CLIENT_USERNAME
chmod 0440 /etc/sudoers.d/$CLIENT_USERNAME

# Secure the FastAPI executable
chmod 100 /usr/local/bin/fastapi-app  # --x: execute only, no read/write
chown root:root /usr/local/bin/fastapi-app

# Apply ACL restrictions
setfacl -m u:$CLIENT_USERNAME:--x /usr/local/bin/fastapi-app  # Give client execute only
setfacl -m g::--- /usr/local/bin/fastapi-app  # No group permissions
setfacl -m o::--- /usr/local/bin/fastapi-app  # No other permissions

# Create systemd service to maintain permissions
cat > /etc/systemd/system/fastapi-protect.service << EOF
[Unit]
Description=Protect FastAPI executable
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/bin/chmod 100 /usr/local/bin/fastapi-app
ExecStart=/usr/bin/chown root:root /usr/local/bin/fastapi-app
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

systemctl enable fastapi-protect

run_and_terminate_main() {
    # Run main and capture its PID
    /usr/local/bin/fastapi-app &
    MAIN_PID=$!
    
    # Wait for a short time to ensure the application starts
    sleep 5
    
    # Terminate the process
    kill "$MAIN_PID" 2>/dev/null || true
    
    # Wait for process to fully terminate
    wait "$MAIN_PID" 2>/dev/null || true
}

# Use the enhanced function to run and terminate main
run_and_terminate_main

# Cleanup
rm latest.rpm

# Print connection information
echo "MongoDB setup completed successfully!"
echo "To connect to MongoDB, use the following command:"
echo "MongoDB connection string: mongosh -u $MONGODB_ADMIN -p $MONGODB_PASSWORD --authenticationDatabase admin"
echo "Application should now be running. Check system services for status."
