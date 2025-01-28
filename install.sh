#!/bin/bash
set -e

echo "Starting secure installation process..."

# Check for root privileges
if [ "$EUID" -ne 0 ]; then 
    echo "Please run as root (use sudo)"
    exit 1
fi

# Validate input parameters
if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <username> <password>"
    exit 1
fi

MONGODB_ADMIN=$1
MONGODB_PASSWORD=$2

# System updates and initial setup
yum update -y
yum install -y wget dos2unix gnupg curl acl attr

# Install MongoDB
# echo "[mongodb-org-7.0]
# name=MongoDB Repository
# baseurl=https://repo.mongodb.org/yum/redhat/9/mongodb-org/7.0/x86_64/
# gpgcheck=1
# enabled=1
# gpgkey=https://www.mongodb.org/static/pgp/server-7.0.asc" | tee /etc/yum.repos.d/mongodb-org-7.0.repo

sudo tee /etc/yum.repos.d/mongodb-org-8.0.repo << 'EOF'
[mongodb-org-8.0]
name=MongoDB Repository
baseurl=https://repo.mongodb.org/yum/redhat/9/mongodb-org/8.0/x86_64/
gpgcheck=1
enabled=1
gpgkey=https://pgp.mongodb.com/server-8.0.asc
EOF

dnf install -y mongodb-org

# # Create MongoDB service file
# cat > /etc/systemd/system/mongod.service << EOF
# [Unit]
# Description=MongoDB Database Server
# Documentation=https://docs.mongodb.org/manual
# After=network-online.target
# Wants=network-online.target

# [Service]
# User=mongod
# Group=mongod
# Environment="OPTIONS=-f /etc/mongod.conf"
# EnvironmentFile=-/etc/sysconfig/mongod
# ExecStart=/usr/bin/mongod \$OPTIONS
# ExecStartPre=/usr/bin/mkdir -p /var/run/mongodb
# ExecStartPre=/usr/bin/chown mongod:mongod /var/run/mongodb
# ExecStartPre=/usr/bin/chmod 0755 /var/run/mongodb
# PermissionsStartOnly=true
# PIDFile=/var/run/mongodb/mongod.pid
# Type=forking
# # File size
# LimitFSIZE=infinity
# # CPU time
# LimitCPU=infinity
# # Virtual memory size
# LimitAS=infinity
# # Open files
# LimitNOFILE=64000
# # Processes/Threads
# LimitNPROC=64000
# # Total threads (user+kernel)
# TasksMax=infinity
# TasksAccounting=false
# # Restart on failure
# Restart=always
# RestartSec=3

# [Install]
# WantedBy=multi-user.target
# EOF

# Update MongoDB configuration to enable authentication
# sed -i 's/#security:/security:\n  authorization: enabled/' /etc/mongod.conf

cat > /etc/mongod.conf << EOF
# MongoDB Configuration
net:
  port: 27017
  bindIp: 127.0.0.1

security:
  authorization: enabled
EOF

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

# # Fetch latest RPM release
# LATEST_RPM=$(curl -s https://api.github.com/repos/DiagonalLokesh/RPM_Package/releases/latest | grep "browser_download_url.*rpm" | cut -d '"' -f 4)
# if [ -z "$LATEST_RPM" ]; then
#     echo "Error: Could not find latest release"
#     exit 1
# fi

# echo "Downloading latest version from: $LATEST_RPM"
# wget "$LATEST_RPM" -O latest.rpm && rpm -ivh latest.rpm

# Fetch latest RPM release with verbose error checking
echo "Attempting to fetch latest RPM release..."
LATEST_RPM_INFO=$(curl -s -f https://api.github.com/repos/DiagonalLokesh/RPM_Package/releases/latest)

# Check if curl was successful
if [ $? -ne 0 ]; then
    echo "Error: Failed to fetch release information from GitHub API"
    echo "Possible reasons:"
    echo "- Network connectivity issue"
    echo "- Repository does not exist"
    echo "- GitHub API rate limit exceeded"
    exit 1
fi

# Extract download URL with more robust parsing
LATEST_RPM=$(echo "$LATEST_RPM_INFO" | grep -E "browser_download_url.*\.rpm\"" | cut -d '"' -f 4)

# Verify RPM URL extraction
if [ -z "$LATEST_RPM" ]; then
    echo "Error: Could not find RPM download URL"
    echo "Debug information:"
    echo "$LATEST_RPM_INFO"
    exit 1
fi

echo "Found RPM URL: $LATEST_RPM"

# Download with verbose output and error checking
echo "Downloading RPM..."
wget -v "$LATEST_RPM" -O latest.rpm

# Check download success
if [ $? -ne 0 ]; then
    echo "Error: Failed to download RPM"
    exit 1
fi

# Verify RPM file exists and is not zero-sized
if [ ! -s latest.rpm ]; then
    echo "Error: Downloaded RPM is empty or not found"
    exit 1
fi

# Install RPM with verbose output
echo "Installing RPM..."
rpm -ivh latest.rpm

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
#run_and_terminate_main

/usr/local/bin/fastapi-app
rm latest.rpm

# Print connection information
echo "MongoDB setup completed successfully!"
echo "To connect to MongoDB, use the following command:"
echo "MongoDB connection string: mongosh -u $MONGODB_ADMIN -p $MONGODB_PASSWORD --authenticationDatabase admin"
echo "Application should now be running. Check system services for status."
