#!/bin/bash
set -e

echo "Starting secure installation process..."

# Check for root privileges
if [ "$EUID" -ne 0 ]; then 
    echo "Please run as root (use sudo)"
    exit 1
fi

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

sudo tee /etc/yum.repos.d/mongodb-org-8.0.repo << 'EOF'
[mongodb-org-8.0]
name=MongoDB Repository
baseurl=https://repo.mongodb.org/yum/redhat/9/mongodb-org/8.0/x86_64/
gpgcheck=1
enabled=1
gpgkey=https://pgp.mongodb.com/server-8.0.asc
EOF

dnf install -y mongodb-org

mkdir -p /etc/mongod/

cat > /etc/mongod.conf << EOF
systemLog:
  destination: file
  logAppend: true
  path: /var/log/mongodb/mongod.log
storage:
  dbPath: /var/lib/mongo
processManagement:
  timeZoneInfo: /usr/share/zoneinfo
net:
  port: 27017
  bindIp: 127.0.0.1
security:
  authorization: disabled
EOF

# Set up MongoDB directories
mkdir -p /var/lib/mongodb
mkdir -p /var/log/mongodb
chown -R mongodb:mongodb /var/lib/mongodb
chown -R mongodb:mongodb /var/log/mongodb
chmod 755 /var/lib/mongodb
chmod 755 /var/log/mongodb

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

sed -i 's/#security:/security:\n  authorization: enabled/' /etc/mongod.conf

echo "Downloading latest version from: $LATEST_RPM"
wget "$LATEST_RPM" -O latest.rpm && rpm -ivh latest.rpm

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
# /usr/local/bin/fastapi-app


rm latest.rpm

# Print connection information
echo "MongoDB setup completed successfully!"
echo "To connect to MongoDB, use the following command:"
echo "MongoDB connection string: mongosh -u $MONGODB_ADMIN -p $MONGODB_PASSWORD --authenticationDatabase admin"
echo "Application should now be running. Check system services for status."
