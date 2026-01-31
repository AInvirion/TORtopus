# TORtopus

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![GitHub Issues](https://img.shields.io/github/issues/ainvirion/TORtopus.svg)](https://github.com/ainvirion/TORtopus/issues)
[![GitHub Pull Requests](https://img.shields.io/github/issues-pr/ainvirion/TORtopus.svg)](https://github.com/ainvirion/TORtopus/pulls)

> Automated Ubuntu server hardening with integrated Tor proxy capabilities

## About

TORtopus is an automated security hardening and proxy configuration tool for Ubuntu servers. It combines best-practice security hardening with a flexible Squid + Tor proxy setup, allowing you to route traffic through Tor for enhanced privacy.

**Use Cases:**
- Secure remote server deployment
- Privacy-enhanced web browsing
- Anonymous API testing
- Security research environments

## Features

**Security Hardening**
- SSH key-only authentication with configurable port
- UFW firewall with automatic configuration
- fail2ban intrusion prevention
- Automatic security updates
- Configuration backups with rollback capability

**Proxy Capabilities**
- Dual-mode proxy: Direct or Tor-routed traffic
- Multi-user authentication with alphanumeric password support
- Auto-generated first user credentials
- HTTP proxy (port 3128) and SOCKS5 (port 9050)
- Web dashboard for user management

## Getting Started

### Prerequisites

- Ubuntu 20.04 LTS, 22.04 LTS, or 24.04 LTS
- Root or sudo access
- SSH key pair for key-based authentication

### Installation

```bash
# Download installer
wget https://raw.githubusercontent.com/AInvirion/TORtopus/main/install.sh

# Make executable and run
chmod +x install.sh
sudo ./install.sh
```

The installer is interactive and will guide you through:
1. System updates and security hardening
2. SSH port configuration (optional)
3. Firewall and fail2ban setup
4. Tor and Squid proxy installation
5. User creation and proxy mode selection

## Usage

### Testing the Proxy

```bash
# Test HTTP proxy (use credentials from installation)
curl --proxy-anyauth -x 'http://username:password@your-server:3128' https://ifconfig.me
```

### Management Commands

```bash
tortopus-user add <username>        # Add proxy user
tortopus-user list                  # List users
tortopus-config --mode [direct|tor] # Switch proxy mode
tortopus-diagnostic                 # Run system health check
tortopus-rollback                   # Restore backups
```

### Web Dashboard

```bash
# Install dashboard
sudo ./install-dashboard.sh

# Access via SSH tunnel
ssh -L 5000:127.0.0.1:5000 root@your-server -p SSH_PORT
# Open browser: http://localhost:5000
```

## Documentation

- [Installation Guide](docs/INSTALLATION.md) - Detailed installation instructions
- [Usage Guide](docs/USAGE.md) - Complete usage examples and proxy modes
- [Configuration](docs/CONFIGURATION.md) - Configuration files and customization
- [Web Dashboard](docs/DASHBOARD.md) - Dashboard setup and usage
- [Troubleshooting](docs/TROUBLESHOOTING.md) - Common issues and solutions

## Contributing

We welcome contributions from the community! Please read our [Contributing Guidelines](CONTRIBUTING.md) before submitting a pull request.

## Security

If you discover a security vulnerability, please follow our [Security Policy](SECURITY.md).

## License

This project is licensed under the Apache License 2.0 - see the [LICENSE](LICENSE) file for details.

Copyright (c) 2025-2026 AInvirion LLC. All Rights Reserved.

---

**Disclaimer**: This tool is provided for legitimate security hardening and privacy protection purposes. Users are responsible for ensuring compliance with all applicable laws and regulations. The authors assume no liability for misuse.
