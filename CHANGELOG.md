# Changelog

All notable changes to TORtopus will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Planned
- IPv6 support
- Advanced Tor circuit configuration
- Docker deployment option
- Ansible playbook version

## [1.1.0] - 2026-03-21

### Added
- Privoxy as HTTP-to-SOCKS bridge for proper Tor routing
- `upgrade.sh` script for upgrading existing installations
- Privoxy service and port checks in diagnostic tools

### Fixed
- **HTTPS proxy support**: Fixed 501 error on CONNECT requests when using Tor mode
  - Squid cannot speak SOCKS directly to Tor's port 9050
  - Now routes: Squid (HTTP) → Privoxy (8118) → Tor (SOCKS 9050)
- Updated `tortopus-config` to manage Privoxy when switching modes
- Fixed `local` keyword used outside functions in diagnostic script

### Changed
- `cache_peer` now uses port 8118 (Privoxy) instead of 9050 (Tor) directly
- Updated all verification and diagnostic scripts to check Privoxy

### Upgrade
Existing installations can upgrade with:
```bash
curl -sSL https://raw.githubusercontent.com/AInvirion/TORtopus/main/upgrade.sh | sudo bash
```

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
