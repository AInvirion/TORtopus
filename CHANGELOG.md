# Changelog

All notable changes to TORtopus will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Planned
- Support for custom SSH ports
- IPv6 support
- Advanced Tor circuit configuration
- Web-based administration panel
- Docker deployment option
- Ansible playbook version

## [1.0.0] - 2026-01-31

### Added
- Initial release of TORtopus
- Interactive installer for Ubuntu 20.04, 22.04, and 24.04 LTS
- SSH hardening with key-only authentication
- UFW firewall configuration
- fail2ban intrusion prevention with SSH and Squid monitoring
- Automatic security updates (unattended-upgrades)
- Tor installation and configuration (SOCKS5 on port 9050)
- Squid proxy installation (HTTP on port 3128)
- Multi-user HTTP digest authentication for proxy
- Dual-mode proxy support (direct and Tor-routed traffic)
- Configuration backup and rollback system
- Management scripts in `/usr/local/bin`:
  - `tortopus-user` - User management (add/remove/list/passwd)
  - `tortopus-config` - Proxy mode switching (direct/tor)
  - `tortopus-rollback` - Configuration restoration
- Comprehensive README with usage examples and troubleshooting

### Security
- SSH password authentication disabled (key-only)
- Strong SSH ciphers and KEX algorithms (Curve25519, AES-GCM, ChaCha20-Poly1305)
- fail2ban monitoring for brute-force protection
- Automatic daily security updates
- Secure file permissions for sensitive configurations
- Configuration backups stored in `/var/backups/tortopus/`

[Unreleased]: https://github.com/AInvirion/TORtopus/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/AInvirion/TORtopus/releases/tag/v1.0.0
