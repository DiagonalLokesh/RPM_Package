#!/bin/bash
set -e

echo "Starting secure installation process..."

# # Check for root privileges
# if [ "$EUID" -ne 0 ]; then 
#     echo "Please run as root (use sudo)"
#     exit 1
# fi

# # Validate input parameters
# if [ "$#" -ne 2 ]; then
#     echo "Usage: $0 <username> <password>"
#     exit 1
# fi

# MONGODB_ADMIN=$1
# MONGODB_PASSWORD=$2

# System updates and initial setup
yum update
yum install -y dos2unix gnupg curl acl attr

# Install MongoDB
echo "[mongodb-org-7.0]
name=MongoDB Repository
baseurl=https://repo.mongodb.org/yum/redhat/9/mongodb-org/7.0/x86_64/
gpgcheck=1
enabled=1
gpgkey=https://www.mongodb.org/static/pgp/server-7.0.asc" | sudo tee /etc/yum.repos.d/mongodb-org-7.0.repo

dnf install -y mongodb-org
systemctl start mongod 
systemctl enable mongod

LATEST_DEB=$(curl -s https://api.github.com/repos/DiagonalLokesh/RPM_Package/releases/latest | grep "browser_download_url.*rpm" | cut -d '"' -f 4)
if [ -z "$LATEST_DEB" ]; then
    echo "Error: Could not find latest release"
    exit 1
fi

echo "Downloading latest version from: $LATEST_DEB"
wget "$LATEST_DEB" -O latest.deb && rpm -ivh latest.rpm

# Start app
fastapi-app

echo "Application started at http://localhost:8000"
