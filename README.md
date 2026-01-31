# TORtopus 🐙

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![GitHub Issues](https://img.shields.io/github/issues/ainvirion/TORtopus.svg)](https://github.com/ainvirion/TORtopus/issues)
[![GitHub Pull Requests](https://img.shields.io/github/issues-pr/ainvirion/TORtopus.svg)](https://github.com/ainvirion/TORtopus/pulls)

> Automated Ubuntu server hardening with integrated Tor proxy capabilities

## Table of Contents

- [About](#about)
- [Features](#features)
- [Getting Started](#getting-started)
  - [Prerequisites](#prerequisites)
  - [Installation](#installation)
- [Usage](#usage)
- [Proxy Modes](#proxy-modes)
- [User Management](#user-management)
- [Security](#security)
- [Contributing](#contributing)
- [License](#license)

## About

TORtopus is an automated security hardening and proxy configuration tool for Ubuntu servers. It combines best-practice security hardening with a flexible Squid + Tor proxy setup, allowing you to route traffic through Tor for enhanced privacy.

**Use Cases:**
- Secure remote server deployment
- Privacy-enhanced web browsing
- Anonymous API testing
- Security research environments

## Features

### Security Hardening
- ✅ **SSH Key-Only Authentication** - Disables password authentication
- ✅ **Firewall Configuration** - UFW with sensible defaults
- ✅ **Intrusion Prevention** - fail2ban with SSH protection
- ✅ **Automatic Security Updates** - Unattended upgrades for security patches
- ✅ **Configuration Backups** - Safe rollback of all changes

### Proxy Capabilities
- 🌐 **Dual-Mode Proxy** - Direct or Tor-routed traffic
- 🔐 **Multi-User Authentication** - HTTP digest auth with local user management
- 🧅 **Tor Integration** - Seamless Tor network connectivity
- 📊 **Access Logging** - Track proxy usage

## Getting Started

### Prerequisites

- Ubuntu 20.04 LTS, 22.04 LTS, or 24.04 LTS
- Root or sudo access
- SSH key pair (for key-based authentication)

### Installation

#### Method 1: Direct Download & Execute

```bash
# Download installer
wget https://raw.githubusercontent.com/AInvirion/TORtopus/main/install.sh

# Make executable
chmod +x install.sh

# Run installer
sudo ./install.sh
```

#### Method 2: Git Clone

```bash
# Clone repository
git clone https://github.com/AInvirion/TORtopus.git

# Navigate to directory
cd TORtopus

# Run installer
sudo ./install.sh
```

#### Method 3: Remote Execution

```bash
# Execute directly from GitHub
curl -sSL https://raw.githubusercontent.com/AInvirion/TORtopus/main/install.sh | sudo bash
```

⚠️ **IMPORTANT**: Review the script before running with sudo privileges!

## Usage

### Running the Installer

The installer is interactive and will guide you through:

1. **Security Hardening** - SSH, firewall, fail2ban configuration
2. **Proxy Setup** - Squid and Tor installation
3. **User Management** - Create proxy users with passwords
4. **Mode Selection** - Choose between direct and Tor proxy modes

```bash
sudo ./install.sh
```

### Connecting to the Proxy

After installation, connect using:

```bash
# HTTP Proxy (Direct Mode - Port 3128)
export http_proxy="http://username:password@your-server:3128"
export https_proxy="http://username:password@your-server:3128"

# SOCKS5 Proxy (Tor Mode - Port 9050)
# Configure your application to use SOCKS5 proxy:
# Host: your-server
# Port: 9050
# Auth: username:password
```

### Testing the Connection

```bash
# Test direct proxy
curl -x http://username:password@your-server:3128 https://ifconfig.me

# Test Tor proxy (using SOCKS5)
curl --socks5 username:password@your-server:9050 https://check.torproject.org
```

## Proxy Modes

TORtopus supports two proxy modes:

### 1. Direct Mode (Default)
- Traffic goes directly through Squid
- Faster performance
- Normal IP address visible
- Port: `3128`

### 2. Tor Mode
- All traffic routed through Tor network
- Enhanced privacy and anonymity
- Slower performance
- Exit node IP visible
- Port: `9050` (SOCKS5)

Switch modes anytime:
```bash
sudo tortopus-config --mode [direct|tor]
```

## User Management

### Add Proxy User

```bash
sudo tortopus-user add <username>
```

### Remove Proxy User

```bash
sudo tortopus-user remove <username>
```

### List Proxy Users

```bash
sudo tortopus-user list
```

### Change User Password

```bash
sudo tortopus-user passwd <username>
```

## Configuration Files

After installation, configuration files are located at:

- **Squid**: `/etc/squid/squid.conf`
- **Tor**: `/etc/tor/torrc`
- **Users**: `/etc/squid/passwords`
- **Backups**: `/var/backups/tortopus/`

## Rollback

If needed, restore original configurations:

```bash
sudo tortopus-rollback
```

This restores all backed-up configurations from `/var/backups/tortopus/`.

## Firewall Ports

TORtopus configures UFW with the following ports:

- **SSH**: 22 (or custom port if specified)
- **Squid HTTP Proxy**: 3128
- **Tor SOCKS5**: 9050

## Security Considerations

- 🔑 SSH password authentication is **disabled** - ensure SSH keys are properly configured
- 🔐 All proxy connections require authentication
- 🛡️ fail2ban monitors and blocks brute-force attempts
- 🔄 Automatic security updates are enabled
- 📝 All changes are logged

## Troubleshooting

### SSH Lockout
If you get locked out after hardening:
- Use your hosting provider's console/recovery mode
- Check `/var/backups/tortopus/sshd_config.backup`

### Proxy Not Working
```bash
# Check Squid status
sudo systemctl status squid

# Check Tor status
sudo systemctl status tor

# View logs
sudo tail -f /var/log/squid/access.log
sudo journalctl -u tor -f
```

### Tor Connection Issues
```bash
# Restart Tor
sudo systemctl restart tor

# Check Tor connectivity
curl --socks5 127.0.0.1:9050 https://check.torproject.org
```

## Contributing

We welcome contributions! Please read our [Contributing Guidelines](CONTRIBUTING.md) before submitting a pull request.

## Security

If you discover a security vulnerability, please follow our [Security Policy](SECURITY.md).

## License

This project is licensed under the Apache License 2.0 - see the [LICENSE](LICENSE) file for details.

Copyright (c) 2025-2026 AInvirion LLC. All Rights Reserved.

---

**Disclaimer**: This tool is provided for legitimate security hardening and privacy protection purposes. Users are responsible for ensuring compliance with all applicable laws and regulations. The authors assume no liability for misuse.
