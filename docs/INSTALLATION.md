# Installation Guide

Complete installation instructions for TORtopus.

## System Requirements

- Ubuntu 20.04 LTS, 22.04 LTS, or 24.04 LTS
- Minimum 1GB RAM
- 10GB disk space
- Root or sudo access
- SSH key pair for authentication

## Installation Methods

### Method 1: Direct Download (Recommended)

```bash
# Download installer
wget https://raw.githubusercontent.com/AInvirion/TORtopus/main/install.sh

# Make executable
chmod +x install.sh

# Run installer
sudo ./install.sh
```

### Method 2: Git Clone

```bash
# Clone repository
git clone https://github.com/AInvirion/TORtopus.git

# Navigate to directory
cd TORtopus

# Run installer
sudo ./install.sh
```

### Method 3: Remote Execution

```bash
# Execute directly from GitHub
curl -sSL https://raw.githubusercontent.com/AInvirion/TORtopus/main/install.sh | sudo bash
```

**WARNING**: Always review scripts before running with sudo privileges.

## Installation Process

The installer will guide you through several phases:

### Phase 1: System Updates

The installer updates all system packages to ensure latest security patches.

### Phase 2: Security Hardening

**SSH Configuration**
- Confirms you want SSH hardening
- Detects current SSH port
- Asks if you want to change the SSH port (recommended for security)
- Validates port range (1024-65535) and checks for conflicts
- Disables password authentication
- Enables key-only authentication

**Firewall Configuration**
- Sets up UFW with deny incoming/allow outgoing defaults
- Opens SSH port (current or newly configured)
- Opens Squid proxy port (3128)
- Opens Tor SOCKS5 port (9050)
- Verifies rules before enabling
- Auto-disables if SSH port not allowed (safety feature)

**fail2ban Configuration**
- Configures SSH jail (3 attempts, 2-hour ban)
- Configures Squid jail (10 attempts, 1-hour ban)
- Creates filter for Squid authentication failures

**Automatic Updates**
- Enables unattended-upgrades for security patches
- Configures automatic cleanup

### Phase 3: Proxy Installation

**Tor Installation**
- Installs Tor package
- Configures SOCKS5 on localhost:9050
- Sets up control port for management
- Enables and starts service

**Squid Installation**
- Installs Squid proxy
- Configures HTTP port 3128
- Sets up basic authentication
- Creates password file
- Enables access logging

### Phase 4: User Setup

**Auto-generated First User**
- Creates random username (userXXXXXX format)
- Generates secure 16-character alphanumeric password
- Displays credentials prominently (SAVE THESE!)

**Additional Users** (Optional)
- Prompts to add more users
- Validates usernames (alphanumeric and underscore only)
- Validates passwords (alphanumeric only, 8+ characters)

### Phase 5: Proxy Mode Selection

Choose between:
1. **Direct Mode**: Faster, normal IP visible
2. **Tor Mode**: Slower, routed through Tor network

## Post-Installation

### Verify Installation

```bash
# Check service status
sudo systemctl status squid tor fail2ban

# Run diagnostic
sudo tortopus-diagnostic

# Test proxy
curl --proxy-anyauth -x 'http://username:password@your-server:3128' https://ifconfig.me
```

### Important Notes

1. **Save your credentials**: The auto-generated password won't be shown again
2. **Test SSH key access**: Before logging out, verify you can reconnect with your SSH key
3. **Note your SSH port**: If you changed it, use `-p PORT` when connecting
4. **Backup location**: All backups are in `/var/backups/tortopus/`

### Firewall Ports

After installation, these ports are open:
- **SSH**: 22 (or your custom port)
- **Squid HTTP Proxy**: 3128
- **Tor SOCKS5**: 9050

## Installing Web Dashboard

Optional web interface for user management:

```bash
# Run dashboard installer
sudo ./install-dashboard.sh

# Set admin password when prompted (or use default: changeme123)

# Access via SSH tunnel
ssh -L 5000:127.0.0.1:5000 root@your-server -p SSH_PORT

# Open browser
http://localhost:5000
```

Default credentials:
- Username: `admin`
- Password: `changeme123` (or your custom password)

## Troubleshooting Installation

### SSH Key Not Found

If installer warns about missing SSH key:
```bash
# Check authorized_keys
cat ~/.ssh/authorized_keys

# Add your key
echo "your-public-key" >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

### Service Failed to Start

Check logs:
```bash
# Squid
sudo journalctl -u squid -n 50

# Tor
sudo journalctl -u tor -n 50

# fail2ban
sudo journalctl -u fail2ban -n 50
```

### Firewall Issues

If you get locked out:
- Use hosting provider's console/recovery mode
- Disable firewall: `sudo ufw disable`
- Fix rules and re-enable: `sudo ufw enable`

## Rollback

If installation fails or you want to revert:

```bash
# Restore all backups
sudo tortopus-rollback

# Restart services
sudo systemctl restart sshd squid tor fail2ban
```

Backups include:
- SSH configuration
- Firewall rules
- Squid configuration
- Tor configuration
- fail2ban configuration
