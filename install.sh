#!/bin/bash
#
# TORtopus - Ubuntu Server Hardening + Tor/Squid Proxy Installer
# Copyright (c) 2025-2026 AInvirion LLC
# Licensed under Apache License 2.0
#
# This script performs security hardening and installs Tor+Squid proxy
# WARNING: This script makes significant system changes. Review before running.
#

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
BACKUP_DIR="/var/backups/tortopus"
INSTALL_LOG="/var/log/tortopus-install.log"
SQUID_USERS_FILE="/etc/squid/passwords"
BIN_DIR="/usr/local/bin"

# Version info
VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

#=============================================================================
# Helper Functions
#=============================================================================

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*" | tee -a "$INSTALL_LOG"
}

error() {
    echo -e "${RED}[ERROR]${NC} $*" | tee -a "$INSTALL_LOG" >&2
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*" | tee -a "$INSTALL_LOG"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $*" | tee -a "$INSTALL_LOG"
}

print_banner() {
    echo -e "${BLUE}"
    cat << "EOF"
╔════════════════════════════════════════════════════════════════╗
║                                                                ║
║   ████████╗ ██████╗ ██████╗ ████████╗ ██████╗ ██████╗ ██╗   ██╗███████╗   ║
║   ╚══██╔══╝██╔═══██╗██╔══██╗╚══██╔══╝██╔═══██╗██╔══██╗██║   ██║██╔════╝   ║
║      ██║   ██║   ██║██████╔╝   ██║   ██║   ██║██████╔╝██║   ██║███████╗   ║
║      ██║   ██║   ██║██╔══██╗   ██║   ██║   ██║██╔═══╝ ██║   ██║╚════██║   ║
║      ██║   ╚██████╔╝██║  ██║   ██║   ╚██████╔╝██║     ╚██████╔╝███████║   ║
║      ╚═╝    ╚═════╝ ╚═╝  ╚═╝   ╚═╝    ╚═════╝ ╚═╝      ╚═════╝ ╚══════╝   ║
║                                                                ║
║         Ubuntu Hardening + Tor/Squid Proxy Installer          ║
║                      Version: v1.0.0                           ║
║                                                                ║
╚════════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root (use sudo)"
        exit 1
    fi
}

check_ubuntu() {
    if [[ ! -f /etc/os-release ]]; then
        error "Cannot detect OS. This script is for Ubuntu only."
        exit 1
    fi

    source /etc/os-release

    if [[ "$ID" != "ubuntu" ]]; then
        error "This script is designed for Ubuntu. Detected: $ID"
        exit 1
    fi

    # Check version
    local version_id="${VERSION_ID}"
    if [[ ! "$version_id" =~ ^(20.04|22.04|24.04) ]]; then
        warning "Tested on Ubuntu 20.04, 22.04, and 24.04 LTS. You have: $version_id"
        read -p "Continue anyway? (y/n) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi

    log "Detected: Ubuntu $version_id"
}

create_backup_dir() {
    if [[ ! -d "$BACKUP_DIR" ]]; then
        mkdir -p "$BACKUP_DIR"
        chmod 700 "$BACKUP_DIR"
        log "Created backup directory: $BACKUP_DIR"
    fi
}

backup_file() {
    local file="$1"
    if [[ -f "$file" ]]; then
        local backup_name="$(basename "$file").backup.$(date +%Y%m%d_%H%M%S)"
        cp -a "$file" "$BACKUP_DIR/$backup_name"
        log "Backed up: $file -> $BACKUP_DIR/$backup_name"
    fi
}

confirm_action() {
    local message="$1"
    echo -e "${YELLOW}$message${NC}"
    read -p "Continue? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        warning "Operation cancelled by user"
        return 1
    fi
    return 0
}

#=============================================================================
# System Updates
#=============================================================================

update_system() {
    log "Updating system packages..."

    export DEBIAN_FRONTEND=noninteractive

    apt-get update -qq
    apt-get upgrade -y -qq
    apt-get dist-upgrade -y -qq
    apt-get autoremove -y -qq
    apt-get autoclean -qq

    log "System updated successfully"
}

#=============================================================================
# Security Hardening
#=============================================================================

install_security_packages() {
    log "Installing security packages..."

    local packages=(
        "ufw"
        "fail2ban"
        "unattended-upgrades"
        "apt-listchanges"
        "openssl"
        "apache2-utils"
    )

    export DEBIAN_FRONTEND=noninteractive
    apt-get install -y -qq "${packages[@]}"

    log "Security packages installed"
}

configure_ssh() {
    log "Configuring SSH hardening..."

    local ssh_config="/etc/ssh/sshd_config"

    # Backup original
    backup_file "$ssh_config"

    # Check if SSH keys are configured
    local has_keys=false
    if [[ -f /root/.ssh/authorized_keys ]] && [[ -s /root/.ssh/authorized_keys ]]; then
        has_keys=true
        info "Found SSH authorized_keys for root"
    fi

    # Check for other users with sudo access
    local sudo_users=$(getent group sudo | cut -d: -f4)
    for user in ${sudo_users//,/ }; do
        if [[ -f "/home/$user/.ssh/authorized_keys" ]] && [[ -s "/home/$user/.ssh/authorized_keys" ]]; then
            has_keys=true
            info "Found SSH authorized_keys for user: $user"
        fi
    done

    if [[ "$has_keys" == "false" ]]; then
        error "No SSH keys found in authorized_keys!"
        error "You must add your public key before disabling password auth"
        error "Example: cat ~/.ssh/id_ed25519.pub | ssh root@server 'cat >> ~/.ssh/authorized_keys'"
        return 1
    fi

    # Detect current SSH port to preserve it
    local current_ssh_port=""

    # Method 1: Check current SSH connection
    if [[ -n "${SSH_CONNECTION:-}" ]]; then
        current_ssh_port=$(echo "$SSH_CONNECTION" | awk '{print $4}')
        info "Detected SSH port from active connection: $current_ssh_port"
    fi

    # Method 2: Check what port sshd is listening on
    if [[ -z "$current_ssh_port" ]]; then
        current_ssh_port=$(ss -tlnp 2>/dev/null | grep sshd | grep -oP '(?<=:)\d+(?= )' | head -1)
        if [[ -z "$current_ssh_port" ]]; then
            current_ssh_port=$(netstat -tlnp 2>/dev/null | grep sshd | grep -oP '(?<=:)\d+(?= )' | head -1)
        fi
        if [[ -n "$current_ssh_port" ]]; then
            info "Detected SSH port from listening socket: $current_ssh_port"
        fi
    fi

    # Method 3: Check existing config
    if [[ -z "$current_ssh_port" ]]; then
        current_ssh_port=$(grep "^Port " "$ssh_config" 2>/dev/null | awk '{print $2}')
        if [[ -n "$current_ssh_port" ]]; then
            info "Detected SSH port from config: $current_ssh_port"
        fi
    fi

    # Default to 22 if still not found
    if [[ -z "$current_ssh_port" ]] || [[ ! "$current_ssh_port" =~ ^[0-9]+$ ]]; then
        current_ssh_port=22
        warning "Could not detect SSH port, defaulting to 22"
    fi

    # Ask if user wants to change SSH port
    local ssh_port="$current_ssh_port"

    echo ""
    info "Current SSH port: $current_ssh_port"

    if [[ "$current_ssh_port" == "22" ]]; then
        warning "Port 22 is the default SSH port and commonly targeted by bots"
        info "Using a non-standard port (e.g., 2222, 22871) improves security"
    fi

    echo ""
    read -p "Do you want to change the SSH port? (y/n) " -n 1 -r
    echo

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        while true; do
            read -p "Enter new SSH port (1024-65535, recommend 2222 or higher): " new_port

            # Validate port number
            if [[ ! "$new_port" =~ ^[0-9]+$ ]]; then
                error "Port must be a number"
                continue
            fi

            if [[ "$new_port" -lt 1024 ]] || [[ "$new_port" -gt 65535 ]]; then
                error "Port must be between 1024 and 65535"
                continue
            fi

            if [[ "$new_port" == "3128" ]] || [[ "$new_port" == "9050" ]]; then
                error "Port $new_port is reserved for Squid/Tor"
                continue
            fi

            # Confirm the change
            warning "═══════════════════════════════════════════════════════"
            warning "SSH port will be changed from $current_ssh_port to $new_port"
            warning "Make sure to reconnect using: ssh -p $new_port user@host"
            warning "═══════════════════════════════════════════════════════"
            echo ""
            read -p "Confirm port change to $new_port? (y/n) " -n 1 -r
            echo

            if [[ $REPLY =~ ^[Yy]$ ]]; then
                ssh_port="$new_port"
                log "SSH port will be changed to: $ssh_port"
                break
            else
                info "Port change cancelled, keeping port $current_ssh_port"
                break
            fi
        done
    else
        info "Keeping SSH port: $ssh_port"
    fi

    # Store the SSH port for later use (firewall configuration)
    SSH_PORT="$ssh_port"

    # Apply hardening (using selected port)
    cat > "$ssh_config" << EOF
# TORtopus SSH Configuration
# Generated by TORtopus installer

# Port and listening
Port $ssh_port
AddressFamily any
ListenAddress 0.0.0.0

# Authentication
PermitRootLogin prohibit-password
PubkeyAuthentication yes
PasswordAuthentication no
PermitEmptyPasswords no
ChallengeResponseAuthentication no
UsePAM yes

# Security settings
X11Forwarding no
PrintMotd no
AcceptEnv LANG LC_*
Subsystem sftp /usr/lib/openssh/sftp-server

# Additional hardening
Protocol 2
HostKey /etc/ssh/ssh_host_ed25519_key
HostKey /etc/ssh/ssh_host_rsa_key
KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org,diffie-hellman-group16-sha512,diffie-hellman-group18-sha512
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com,hmac-sha2-512,hmac-sha2-256

# Connection settings
ClientAliveInterval 300
ClientAliveCountMax 2
MaxAuthTries 3
MaxSessions 10
LoginGraceTime 60

# Logging
SyslogFacility AUTH
LogLevel VERBOSE
EOF

    # Test configuration
    if ! sshd -t; then
        error "SSH configuration test failed! Restoring backup..."
        cp "$BACKUP_DIR/sshd_config.backup."* "$ssh_config" 2>/dev/null || true
        return 1
    fi

    warning "SSH will be restarted. Ensure you have an active SSH key!"
    warning "Backup config saved at: $BACKUP_DIR"
    sleep 3

    systemctl restart sshd
    log "SSH hardening complete - Password authentication disabled"
}

configure_firewall() {
    log "Configuring UFW firewall..."

    # Detect actual SSH port (CRITICAL for non-standard ports)
    local ssh_port=""

    # Method 1: Check current SSH connection
    if [[ -n "${SSH_CONNECTION:-}" ]]; then
        ssh_port=$(echo "$SSH_CONNECTION" | awk '{print $4}')
        info "Detected SSH port from connection: $ssh_port"
    fi

    # Method 2: Check what port sshd is actually listening on
    if [[ -z "$ssh_port" ]]; then
        ssh_port=$(ss -tlnp 2>/dev/null | grep sshd | grep -oP '(?<=:)\d+(?= )' | head -1)
        if [[ -z "$ssh_port" ]]; then
            ssh_port=$(netstat -tlnp 2>/dev/null | grep sshd | grep -oP '(?<=:)\d+(?= )' | head -1)
        fi
        if [[ -n "$ssh_port" ]]; then
            info "Detected SSH listening port: $ssh_port"
        fi
    fi

    # Method 3: Check sshd_config
    if [[ -z "$ssh_port" ]]; then
        ssh_port=$(grep "^Port " /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}')
        if [[ -n "$ssh_port" ]]; then
            info "Detected SSH port from config: $ssh_port"
        fi
    fi

    # Default to 22 if still not found
    if [[ -z "$ssh_port" ]] || [[ ! "$ssh_port" =~ ^[0-9]+$ ]]; then
        ssh_port=22
        warning "Could not detect SSH port, defaulting to 22"
    fi

    # CRITICAL WARNING for non-standard ports
    if [[ "$ssh_port" != "22" ]]; then
        warning "═══════════════════════════════════════════════════════"
        warning "NON-STANDARD SSH PORT DETECTED: $ssh_port"
        warning "The firewall will allow this port. Verify this is correct!"
        warning "═══════════════════════════════════════════════════════"
        sleep 3
    fi

    # Reset to defaults
    ufw --force reset

    # Default policies
    ufw default deny incoming
    ufw default allow outgoing

    # Allow SSH (MOST IMPORTANT - Do this first!)
    info "Allowing SSH on port $ssh_port/tcp"
    ufw allow "$ssh_port/tcp" comment 'SSH'

    # Allow Squid proxy
    info "Allowing Squid proxy on port 3128/tcp"
    ufw allow 3128/tcp comment 'Squid Proxy'

    # Allow Tor SOCKS
    info "Allowing Tor SOCKS5 on port 9050/tcp"
    ufw allow 9050/tcp comment 'Tor SOCKS5'

    # Show rules before enabling
    echo ""
    warning "Firewall rules to be applied:"
    ufw show added
    echo ""

    # Final safety check
    warning "═══════════════════════════════════════════════════════"
    warning "ABOUT TO ENABLE FIREWALL"
    warning "SSH Port $ssh_port will be allowed"
    warning "If this port is wrong, you may be locked out!"
    warning "═══════════════════════════════════════════════════════"

    if ! confirm_action "Enable firewall with these rules?"; then
        warning "Firewall configuration cancelled"
        return 0
    fi

    # Enable firewall
    ufw --force enable

    # Verify SSH port is allowed
    if ! ufw status | grep -q "$ssh_port.*ALLOW"; then
        error "CRITICAL: SSH port $ssh_port is not allowed in firewall!"
        error "Disabling firewall for safety..."
        ufw disable
        return 1
    fi

    log "Firewall configured and enabled successfully"
    log "SSH port $ssh_port is allowed"
}

configure_fail2ban() {
    log "Configuring fail2ban..."

    # Backup original jail.local if exists
    [[ -f /etc/fail2ban/jail.local ]] && backup_file /etc/fail2ban/jail.local

    # Ensure Squid log file exists (fail2ban needs it)
    if [[ ! -f /var/log/squid/access.log ]]; then
        mkdir -p /var/log/squid
        touch /var/log/squid/access.log
        chown proxy:proxy /var/log/squid/access.log 2>/dev/null || chown root:root /var/log/squid/access.log
        chmod 640 /var/log/squid/access.log
    fi

    # Create jail.local
    cat > /etc/fail2ban/jail.local << 'EOF'
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5
destemail = root@localhost
sendername = Fail2Ban
action = %(action_mw)s

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 7200

[squid]
enabled = true
port = 3128
filter = squid
logpath = /var/log/squid/access.log
maxretry = 10
bantime = 3600
EOF

    # Create squid filter
    cat > /etc/fail2ban/filter.d/squid.conf << 'EOF'
[Definition]
failregex = ^.*TCP_DENIED/407.*<HOST>.*$
ignoreregex =
EOF

    systemctl enable fail2ban
    systemctl restart fail2ban

    # Verify fail2ban started successfully
    sleep 2
    if systemctl is-active --quiet fail2ban; then
        log "fail2ban configured and started"
    else
        warning "fail2ban may have issues, check: journalctl -u fail2ban -n 20"
    fi
}

configure_auto_updates() {
    log "Configuring automatic security updates..."

    backup_file /etc/apt/apt.conf.d/50unattended-upgrades

    cat > /etc/apt/apt.conf.d/50unattended-upgrades << 'EOF'
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}-security";
    "${distro_id}ESMApps:${distro_codename}-apps-security";
    "${distro_id}ESM:${distro_codename}-infra-security";
};
Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::MinimalSteps "true";
Unattended-Upgrade::InstallOnShutdown "false";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
EOF

    cat > /etc/apt/apt.conf.d/20auto-upgrades << 'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Unattended-Upgrade "1";
EOF

    log "Automatic security updates enabled"
}

#=============================================================================
# Tor + Squid Installation
#=============================================================================

install_tor() {
    log "Installing Tor..."

    export DEBIAN_FRONTEND=noninteractive
    apt-get install -y -qq tor

    backup_file /etc/tor/torrc

    cat > /etc/tor/torrc << 'EOF'
# TORtopus Tor Configuration

# SOCKS proxy (localhost only for security)
SOCKSPort 127.0.0.1:9050

# Control port (for management)
ControlPort 9051

# Logging
Log notice file /var/log/tor/notices.log

# Performance
NumEntryGuards 8
CircuitBuildTimeout 30

# Security
CookieAuthentication 1
DataDirectory /var/lib/tor
EOF

    # For Ubuntu's multi-instance Tor setup, need to handle both
    systemctl enable tor
    systemctl restart tor

    # Also ensure the actual instance is running
    if systemctl list-units "tor@*" --all | grep -q "tor@default"; then
        systemctl enable tor@default
        systemctl restart tor@default
    fi

    # Wait for Tor to start
    sleep 5

    # Verify Tor is running
    if systemctl is-active --quiet tor; then
        log "Tor installed and running"
    else
        error "Tor failed to start"
        journalctl -u tor -n 20
        return 1
    fi
}

install_squid() {
    log "Installing Squid..."

    export DEBIAN_FRONTEND=noninteractive
    apt-get install -y -qq squid

    backup_file /etc/squid/squid.conf

    # Create password file
    mkdir -p "$(dirname "$SQUID_USERS_FILE")"
    touch "$SQUID_USERS_FILE"
    chmod 640 "$SQUID_USERS_FILE"
    chown root:proxy "$SQUID_USERS_FILE"

    cat > /etc/squid/squid.conf << 'EOF'
# TORtopus Squid Configuration

# HTTP port
http_port 3128

# Authentication - Basic (better CONNECT tunnel compatibility)
auth_param basic program /usr/lib/squid/basic_ncsa_auth /etc/squid/passwords
auth_param basic children 5
auth_param basic realm TORtopus Proxy
auth_param basic credentialsttl 2 hours

# ACLs
acl authenticated proxy_auth REQUIRED
acl localhost src 127.0.0.1/32
acl to_localhost dst 127.0.0.0/8
acl localnet src 10.0.0.0/8
acl localnet src 172.16.0.0/12
acl localnet src 192.168.0.0/16
acl SSL_ports port 443
acl Safe_ports port 80
acl Safe_ports port 21
acl Safe_ports port 443
acl Safe_ports port 70
acl Safe_ports port 210
acl Safe_ports port 1025-65535
acl Safe_ports port 280
acl Safe_ports port 488
acl Safe_ports port 591
acl Safe_ports port 777
acl CONNECT method CONNECT

# Access rules
http_access deny !Safe_ports
http_access deny CONNECT !SSL_ports
http_access allow localhost
http_access allow authenticated
http_access deny all

# Caching
cache_dir ufs /var/spool/squid 100 16 256
cache_mem 256 MB
maximum_object_size 4 MB
minimum_object_size 0 KB
maximum_object_size_in_memory 512 KB

# Logging
access_log /var/log/squid/access.log squid
cache_log /var/log/squid/cache.log
cache_store_log none

# DNS
dns_nameservers 8.8.8.8 8.8.4.4

# Performance
refresh_pattern ^ftp: 1440 20% 10080
refresh_pattern ^gopher: 1440 0% 1440
refresh_pattern -i (/cgi-bin/|\?) 0 0% 0
refresh_pattern . 0 20% 4320

# Coredumps
coredump_dir /var/spool/squid

# Shutdown
shutdown_lifetime 10 seconds

# Forwarding (can be configured to use Tor)
# never_direct allow all
# cache_peer 127.0.0.1 parent 9050 0 no-query no-digest default
EOF

    # Initialize cache directories
    squid -z 2>/dev/null || true

    systemctl enable squid
    systemctl restart squid

    # Wait for Squid
    sleep 3

    if systemctl is-active --quiet squid; then
        log "Squid installed and running"
    else
        error "Squid failed to start"
        journalctl -u squid -n 20
        return 1
    fi
}

#=============================================================================
# User Management
#=============================================================================

add_proxy_user() {
    local username="$1"

    if [[ -z "$username" ]]; then
        error "Username cannot be empty"
        return 1
    fi

    # Check if user exists
    if grep -q "^$username:" "$SQUID_USERS_FILE" 2>/dev/null; then
        warning "User '$username' already exists"
        read -p "Update password? (y/n) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            return 0
        fi
    fi

    # Prompt for password
    local password
    while true; do
        read -s -p "Enter password for '$username' (alphanumeric only): " password
        echo

        # Validate alphanumeric only
        if [[ ! "$password" =~ ^[a-zA-Z0-9]+$ ]]; then
            error "Password must contain only letters and numbers (no special characters)"
            continue
        fi

        if [[ ${#password} -lt 8 ]]; then
            error "Password must be at least 8 characters long"
            continue
        fi

        read -s -p "Confirm password: " password_confirm
        echo

        if [[ "$password" == "$password_confirm" ]]; then
            break
        else
            error "Passwords do not match. Try again."
        fi
    done

    # Add or update user with htpasswd
    if grep -q "^$username:" "$SQUID_USERS_FILE" 2>/dev/null; then
        # Update existing user
        htpasswd -b "$SQUID_USERS_FILE" "$username" "$password" &>/dev/null
    else
        # Add new user
        htpasswd -b "$SQUID_USERS_FILE" "$username" "$password" &>/dev/null
    fi

    log "User '$username' added/updated successfully"
}

create_management_scripts() {
    log "Creating management scripts..."

    # tortopus-user script
    cat > "$BIN_DIR/tortopus-user" << 'EOFUSER'
#!/bin/bash
# TORtopus User Management Script

SQUID_USERS_FILE="/etc/squid/passwords"
REALM="TORtopus Proxy"

show_usage() {
    echo "Usage: tortopus-user <command> [username]"
    echo ""
    echo "Commands:"
    echo "  add <username>      Add a new proxy user"
    echo "  remove <username>   Remove a proxy user"
    echo "  list                List all proxy users"
    echo "  passwd <username>   Change user password"
    echo ""
}

add_user() {
    local username="$1"
    [[ -z "$username" ]] && { echo "Error: Username required"; exit 1; }

    if grep -q "^$username:" "$SQUID_USERS_FILE" 2>/dev/null; then
        echo "User '$username' already exists. Use 'passwd' to change password."
        exit 1
    fi

    htpasswd -c "$SQUID_USERS_FILE" "$username"
    systemctl reload squid
    echo "User '$username' added successfully"
}

remove_user() {
    local username="$1"
    [[ -z "$username" ]] && { echo "Error: Username required"; exit 1; }

    if ! grep -q "^$username:" "$SQUID_USERS_FILE" 2>/dev/null; then
        echo "User '$username' not found"
        exit 1
    fi

    sed -i "/^$username:/d" "$SQUID_USERS_FILE"
    systemctl reload squid
    echo "User '$username' removed successfully"
}

list_users() {
    if [[ ! -f "$SQUID_USERS_FILE" ]] || [[ ! -s "$SQUID_USERS_FILE" ]]; then
        echo "No users configured"
        exit 0
    fi

    echo "Configured proxy users:"
    cut -d: -f1 "$SQUID_USERS_FILE" | sort | sed 's/^/  - /'
}

change_password() {
    local username="$1"
    [[ -z "$username" ]] && { echo "Error: Username required"; exit 1; }

    if ! grep -q "^$username:" "$SQUID_USERS_FILE" 2>/dev/null; then
        echo "User '$username' not found"
        exit 1
    fi

    htpasswd "$SQUID_USERS_FILE" "$username"
    systemctl reload squid
    echo "Password for '$username' changed successfully"
}

if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root"
    exit 1
fi

case "${1:-}" in
    add)
        add_user "$2"
        ;;
    remove)
        remove_user "$2"
        ;;
    list)
        list_users
        ;;
    passwd)
        change_password "$2"
        ;;
    *)
        show_usage
        exit 1
        ;;
esac
EOFUSER

    chmod +x "$BIN_DIR/tortopus-user"

    # tortopus-config script
    cat > "$BIN_DIR/tortopus-config" << 'EOFCONFIG'
#!/bin/bash
# TORtopus Configuration Script

SQUID_CONF="/etc/squid/squid.conf"

show_usage() {
    echo "Usage: tortopus-config --mode [direct|tor]"
    echo ""
    echo "Modes:"
    echo "  direct  - Direct proxy (faster, no anonymity)"
    echo "  tor     - Route through Tor (slower, anonymous)"
    echo ""
}

enable_tor_mode() {
    echo "Enabling Tor mode..."

    # Check if already enabled
    if grep -q "^cache_peer 127.0.0.1 parent 9050" "$SQUID_CONF"; then
        echo "Tor mode already enabled"
        exit 0
    fi

    # Backup
    cp "$SQUID_CONF" "$SQUID_CONF.bak"

    # Enable Tor forwarding
    sed -i 's/^# never_direct allow all/never_direct allow all/' "$SQUID_CONF"
    sed -i 's/^# cache_peer 127.0.0.1 parent 9050/cache_peer 127.0.0.1 parent 9050/' "$SQUID_CONF"

    systemctl restart squid
    echo "Tor mode enabled. All traffic will route through Tor."
}

enable_direct_mode() {
    echo "Enabling direct mode..."

    # Check if already disabled
    if grep -q "^# cache_peer 127.0.0.1 parent 9050" "$SQUID_CONF"; then
        echo "Direct mode already enabled"
        exit 0
    fi

    # Backup
    cp "$SQUID_CONF" "$SQUID_CONF.bak"

    # Disable Tor forwarding
    sed -i 's/^never_direct allow all/# never_direct allow all/' "$SQUID_CONF"
    sed -i 's/^cache_peer 127.0.0.1 parent 9050/# cache_peer 127.0.0.1 parent 9050/' "$SQUID_CONF"

    systemctl restart squid
    echo "Direct mode enabled. Traffic will not route through Tor."
}

if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root"
    exit 1
fi

case "${1:-}" in
    --mode)
        case "${2:-}" in
            tor)
                enable_tor_mode
                ;;
            direct)
                enable_direct_mode
                ;;
            *)
                show_usage
                exit 1
                ;;
        esac
        ;;
    *)
        show_usage
        exit 1
        ;;
esac
EOFCONFIG

    chmod +x "$BIN_DIR/tortopus-config"

    # tortopus-rollback script
    cat > "$BIN_DIR/tortopus-rollback" << 'EOFROLLBACK'
#!/bin/bash
# TORtopus Rollback Script

BACKUP_DIR="/var/backups/tortopus"

if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root"
    exit 1
fi

if [[ ! -d "$BACKUP_DIR" ]]; then
    echo "No backups found at $BACKUP_DIR"
    exit 1
fi

echo "Available backups:"
ls -1 "$BACKUP_DIR"
echo ""
echo "WARNING: This will restore configuration files from backups."
read -p "Continue? (y/n) " -n 1 -r
echo

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Rollback cancelled"
    exit 0
fi

# Restore SSH config
if ls "$BACKUP_DIR"/sshd_config.backup.* 1> /dev/null 2>&1; then
    latest_ssh=$(ls -t "$BACKUP_DIR"/sshd_config.backup.* | head -1)
    cp "$latest_ssh" /etc/ssh/sshd_config
    echo "Restored: /etc/ssh/sshd_config"
fi

# Restore Squid config
if ls "$BACKUP_DIR"/squid.conf.backup.* 1> /dev/null 2>&1; then
    latest_squid=$(ls -t "$BACKUP_DIR"/squid.conf.backup.* | head -1)
    cp "$latest_squid" /etc/squid/squid.conf
    echo "Restored: /etc/squid/squid.conf"
fi

# Restore Tor config
if ls "$BACKUP_DIR"/torrc.backup.* 1> /dev/null 2>&1; then
    latest_tor=$(ls -t "$BACKUP_DIR"/torrc.backup.* | head -1)
    cp "$latest_tor" /etc/tor/torrc
    echo "Restored: /etc/tor/torrc"
fi

echo ""
echo "Rollback complete. Restart services manually if needed:"
echo "  sudo systemctl restart sshd"
echo "  sudo systemctl restart squid"
echo "  sudo systemctl restart tor"
EOFROLLBACK

    chmod +x "$BIN_DIR/tortopus-rollback"

    # tortopus-diagnostic script
    log "Installing diagnostic tool..."

    # Copy diagnostic script if it exists alongside installer
    if [[ -f "$SCRIPT_DIR/tortopus-diagnostic.sh" ]]; then
        cp "$SCRIPT_DIR/tortopus-diagnostic.sh" "$BIN_DIR/tortopus-diagnostic"
        chmod +x "$BIN_DIR/tortopus-diagnostic"
        log "Diagnostic tool installed from local file"
    else
        # If not available locally, download from GitHub
        if command -v curl &>/dev/null; then
            if curl -sSL https://raw.githubusercontent.com/AInvirion/TORtopus/main/tortopus-diagnostic.sh -o "$BIN_DIR/tortopus-diagnostic" 2>/dev/null; then
                chmod +x "$BIN_DIR/tortopus-diagnostic"
                log "Diagnostic tool downloaded from GitHub"
            else
                warning "Could not download diagnostic tool - will be available in next release"
            fi
        else
            warning "curl not available - diagnostic tool not installed"
        fi
    fi

    log "Management scripts created in $BIN_DIR"
}

#=============================================================================
# Interactive Setup
#=============================================================================

interactive_setup() {
    print_banner

    echo "This installer will:"
    echo "  1. Update system packages"
    echo "  2. Install and configure security hardening (SSH, UFW, fail2ban)"
    echo "  3. Install and configure Tor + Squid proxy"
    echo "  4. Create proxy users"
    echo ""

    if ! confirm_action "Ready to begin installation?"; then
        exit 0
    fi

    # System updates
    log "=== Phase 1: System Updates ==="
    update_system

    # Security hardening
    log "=== Phase 2: Security Hardening ==="
    install_security_packages

    if confirm_action "Configure SSH hardening? (Disable password auth, key-only)"; then
        configure_ssh || {
            error "SSH configuration failed. Aborting."
            exit 1
        }
    fi

    if confirm_action "Configure firewall (UFW)?"; then
        configure_firewall
    fi

    if confirm_action "Configure fail2ban?"; then
        configure_fail2ban
    fi

    if confirm_action "Enable automatic security updates?"; then
        configure_auto_updates
    fi

    # Proxy installation
    log "=== Phase 3: Proxy Installation ==="

    if confirm_action "Install Tor?"; then
        install_tor || {
            error "Tor installation failed"
            exit 1
        }
    fi

    if confirm_action "Install Squid?"; then
        install_squid || {
            error "Squid installation failed"
            exit 1
        }
    fi

    # Create management scripts
    create_management_scripts

    # User creation
    log "=== Phase 4: User Setup ==="

    # Auto-generate first user with random credentials
    info "Generating default proxy user..."
    local first_user="user$(openssl rand -hex 3)"
    local first_pass="$(openssl rand -base64 12 | tr -dc 'a-zA-Z0-9' | head -c 16)"

    # Create first user
    htpasswd -b -c "$SQUID_USERS_FILE" "$first_user" "$first_pass" &>/dev/null
    chmod 640 "$SQUID_USERS_FILE"
    chown root:proxy "$SQUID_USERS_FILE" 2>/dev/null || true

    # Save credentials for display
    FIRST_USER="$first_user"
    FIRST_PASS="$first_pass"

    log "Default user created: $first_user"

    # Optional: add more users
    echo ""
    info "A default user has been created automatically."
    info "You can add more users now, or use 'tortopus-user add <username>' later."
    echo ""

    while true; do
        read -p "Add another user? (username or 'done' to finish): " username
        [[ "$username" == "done" ]] && break
        [[ -z "$username" ]] && continue

        add_proxy_user "$username"
    done

    # Proxy mode selection
    echo ""
    echo "Proxy Mode Selection:"
    echo "  1. Direct mode (faster, no anonymity)"
    echo "  2. Tor mode (slower, anonymous)"
    echo ""
    read -p "Select mode (1 or 2): " mode_choice

    case "$mode_choice" in
        2)
            "$BIN_DIR/tortopus-config" --mode tor
            ;;
        *)
            "$BIN_DIR/tortopus-config" --mode direct
            ;;
    esac

    # Final summary
    echo ""
    echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}   Installation Complete!${NC}"
    echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo "Configuration Summary:"
    echo "  - SSH: Port ${SSH_PORT:-22}, Key-only authentication (password disabled)"
    echo "  - Firewall: UFW enabled"
    echo "  - Proxy: Squid on port 3128"
    echo "  - Tor: SOCKS5 on port 9050"
    echo "  - Backups: $BACKUP_DIR"
    echo ""
    echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${YELLOW}   AUTO-GENERATED PROXY CREDENTIALS (Save These!)${NC}"
    echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "  Username: ${GREEN}${FIRST_USER}${NC}"
    echo -e "  Password: ${GREEN}${FIRST_PASS}${NC}"
    echo ""
    echo -e "${YELLOW}  ⚠️  SAVE THESE CREDENTIALS - They won't be shown again!${NC}"
    echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo "Management Commands:"
    echo "  tortopus-user add <username>        - Add proxy user"
    echo "  tortopus-user list                  - List users"
    echo "  tortopus-config --mode [direct|tor] - Switch proxy mode"
    echo "  tortopus-diagnostic                 - Run system health check"
    echo "  tortopus-rollback                   - Restore backups"
    echo ""
    echo "Test Your Proxy:"
    echo "  curl --proxy-anyauth -x 'http://${FIRST_USER}:${FIRST_PASS}@$(hostname -I | awk '{print $1}'):3128' https://ifconfig.me"
    echo ""
    echo -e "${YELLOW}IMPORTANT: SSH password authentication is now disabled.${NC}"
    echo -e "${YELLOW}Ensure you can log in with your SSH key before closing this session!${NC}"
    if [[ -n "${SSH_PORT}" && "${SSH_PORT}" != "22" ]]; then
        echo -e "${YELLOW}Remember to use port ${SSH_PORT} for SSH connections: ssh -p ${SSH_PORT} user@host${NC}"
    fi
    echo ""
}

#=============================================================================
# Main
#=============================================================================

main() {
    # Pre-flight checks
    check_root
    check_ubuntu
    create_backup_dir

    # Initialize log
    touch "$INSTALL_LOG"
    log "TORtopus installer started - Version $VERSION"

    # Run interactive setup
    interactive_setup

    log "Installation completed successfully"
}

# Run main function
main "$@"
