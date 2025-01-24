#!/bin/bash
set -e

echo "Starting secure installation process..."

# Uncomment and modify these checks as needed
# Check for root privileges
if [ "$EUID" -ne 0 ]; then 
    echo "Please run as root (use sudo)"
    exit 1
fi

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
systemctl start mongod 
systemctl enable mongod

# Fetch latest RPM release
LATEST_RPM=$(curl -s https://api.github.com/repos/DiagonalLokesh/RPM_Package/releases/latest | grep "browser_download_url.*rpm" | cut -d '"' -f 4)
if [ -z "$LATEST_RPM" ]; then
    echo "Error: Could not find latest release"
    exit 1
fi

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
# run_and_terminate_main

rm latest.rpm
echo "Application should now be running. Check system services for status."
