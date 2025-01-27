# RPM Package Installer

## Quick Installation

Run the following command to install the package (replace `user`, `diagonal` and `client` with your desired MongoDB username, MongoDB password and client_username):

```bash
curl -sSL https://raw.githubusercontent.com/DiagonalLokesh/RPM_Package/main/install.sh | tr -d '\r' | sudo bash -s -- <mongodb_username> <mongodb_password>
```

#### Test
```bash
curl -sSL https://raw.githubusercontent.com/DiagonalLokesh/RPM_Package/main/install.sh | tr -d '\r' | sudo bash -s -- user diagonal
```
