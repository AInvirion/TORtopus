#!/bin/bash
#
# TORtopus Upgrade Script
# Upgrades an existing TORtopus installation to the latest version
#
# Usage: curl -sSL https://raw.githubusercontent.com/AInvirion/TORtopus/main/upgrade.sh | sudo bash
#

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

REPO_URL="https://raw.githubusercontent.com/AInvirion/TORtopus/main"
BIN_DIR="/usr/local/bin"
BACKUP_DIR="/var/backups/tortopus"
LOG_FILE="/var/log/tortopus/upgrade.log"

log() {
    local msg="[$(date +'%Y-%m-%d %H:%M:%S')] $*"
    echo -e "${GREEN}${msg}${NC}"
    echo "$msg" >> "$LOG_FILE" 2>/dev/null || true
}

error() {
    local msg="[ERROR] $*"
    echo -e "${RED}${msg}${NC}" >&2
    echo "$msg" >> "$LOG_FILE" 2>/dev/null || true
}

warn() {
    local msg="[WARN] $*"
    echo -e "${YELLOW}${msg}${NC}"
    echo "$msg" >> "$LOG_FILE" 2>/dev/null || true
}

info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

# Banner
echo -e "${CYAN}"
cat << "EOF"
╔══════════════════════════════════════════════════════════════╗
║                   TORtopus Upgrade Script                    ║
║              Upgrade to the latest version                   ║
╚══════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

# Check root
if [[ $EUID -ne 0 ]]; then
    error "This script must be run as root"
    exit 1
fi

# Create log directory
mkdir -p "$(dirname "$LOG_FILE")"
mkdir -p "$BACKUP_DIR"

log "Starting TORtopus upgrade..."

#=============================================================================
# Pre-flight Checks
#=============================================================================
log "Running pre-flight checks..."

# Check if TORtopus is installed
if ! command -v tortopus-user &>/dev/null && ! [[ -f /etc/squid/squid.conf ]]; then
    error "TORtopus does not appear to be installed"
    error "Run the installer instead: curl -sSL ${REPO_URL}/install.sh | sudo bash"
    exit 1
fi

info "TORtopus installation detected"

#=============================================================================
# Fix: Install Privoxy (HTTP-to-SOCKS bridge)
#=============================================================================
# This fixes the bug where Squid tried to use Tor's SOCKS port directly

fix_privoxy() {
    log "Checking Privoxy installation..."

    if ! command -v privoxy &>/dev/null; then
        log "Installing Privoxy (HTTP-to-SOCKS bridge for Tor)..."

        export DEBIAN_FRONTEND=noninteractive
        apt-get update -qq
        apt-get install -y -qq privoxy

        # Backup existing config if any
        if [[ -f /etc/privoxy/config ]]; then
            cp /etc/privoxy/config "$BACKUP_DIR/privoxy.config.backup.$(date +%Y%m%d%H%M%S)"
        fi

        # Configure Privoxy
        cat > /etc/privoxy/config << 'EOF'
# TORtopus Privoxy Configuration
# Bridges HTTP (from Squid) to SOCKS5 (Tor)

# Listen on localhost only
listen-address 127.0.0.1:8118

# Forward all traffic to Tor SOCKS proxy
forward-socks5 / 127.0.0.1:9050 .

# Disable logging for privacy
logfile /var/log/privoxy/logfile
debug 0

# Performance settings
keep-alive-timeout 300
socket-timeout 300
EOF

        systemctl enable privoxy
        systemctl restart privoxy

        if systemctl is-active --quiet privoxy; then
            log "Privoxy installed and running"
        else
            error "Privoxy failed to start"
            journalctl -u privoxy -n 10
            return 1
        fi
    else
        info "Privoxy already installed"

        # Ensure it's running
        if ! systemctl is-active --quiet privoxy; then
            log "Starting Privoxy..."
            systemctl start privoxy
        fi
    fi
}

#=============================================================================
# Fix: Update Squid configuration for Privoxy
#=============================================================================

fix_squid_config() {
    log "Checking Squid configuration..."

    local squid_conf="/etc/squid/squid.conf"

    if [[ ! -f "$squid_conf" ]]; then
        warn "Squid config not found at $squid_conf"
        return 0
    fi

    # Check if using old direct Tor config (port 9050)
    if grep -q "cache_peer 127.0.0.1 parent 9050" "$squid_conf"; then
        log "Fixing Squid configuration to use Privoxy instead of direct Tor..."

        # Backup current config
        cp "$squid_conf" "$BACKUP_DIR/squid.conf.backup.$(date +%Y%m%d%H%M%S)"

        # Update to use Privoxy (port 8118) instead of Tor directly (port 9050)
        sed -i 's/cache_peer 127.0.0.1 parent 9050/cache_peer 127.0.0.1 parent 8118/g' "$squid_conf"

        # Also fix commented version for consistency
        sed -i 's/# cache_peer 127.0.0.1 parent 9050/# cache_peer 127.0.0.1 parent 8118/g' "$squid_conf"

        log "Squid configuration updated"

        # Restart Squid to apply changes
        systemctl restart squid

        if systemctl is-active --quiet squid; then
            log "Squid restarted successfully"
        else
            error "Squid failed to restart"
            journalctl -u squid -n 10
            return 1
        fi
    else
        info "Squid configuration already up to date"
    fi
}

#=============================================================================
# Update Management Scripts
#=============================================================================

update_scripts() {
    log "Updating management scripts..."

    local scripts=("tortopus-user" "tortopus-config" "tortopus-rollback" "tortopus-diagnostic")

    for script in "${scripts[@]}"; do
        info "Downloading $script..."

        if curl -sSL "${REPO_URL}/tools/${script}" -o "/tmp/${script}.new" 2>/dev/null; then
            # Check if download was successful (not a 404 page)
            if head -1 "/tmp/${script}.new" | grep -q "^#!/bin/bash"; then
                # Backup old version if exists
                if [[ -f "${BIN_DIR}/${script}" ]]; then
                    cp "${BIN_DIR}/${script}" "$BACKUP_DIR/${script}.backup.$(date +%Y%m%d%H%M%S)"
                fi

                mv "/tmp/${script}.new" "${BIN_DIR}/${script}"
                chmod +x "${BIN_DIR}/${script}"
                log "Updated: $script"
            else
                warn "Downloaded file for $script is not valid, skipping"
                rm -f "/tmp/${script}.new"
            fi
        else
            warn "Could not download $script"
        fi
    done
}


#=============================================================================
# Update Dashboard
#=============================================================================

update_dashboard() {
    local dashboard_dir="/opt/tortopus-dashboard"

    # Check if dashboard is installed
    if [[ ! -d "$dashboard_dir" ]]; then
        info "Dashboard not installed, skipping dashboard update"
        return 0
    fi

    log "Updating dashboard..."

    # Backup current files
    if [[ -f "$dashboard_dir/app.py" ]]; then
        cp "$dashboard_dir/app.py" "$BACKUP_DIR/dashboard-app.py.backup.$(date +%Y%m%d%H%M%S)"
    fi

    # Download new dashboard files
    if curl -sSL "${REPO_URL}/dashboard/app.py" -o "/tmp/app.py.new" 2>/dev/null; then
        mv "/tmp/app.py.new" "$dashboard_dir/app.py"
        log "Updated: app.py"
    else
        warn "Could not download app.py"
    fi

    # Create templates directory if needed
    mkdir -p "$dashboard_dir/templates"

    if curl -sSL "${REPO_URL}/dashboard/templates/index.html" -o "/tmp/index.html.new" 2>/dev/null; then
        mv "/tmp/index.html.new" "$dashboard_dir/templates/index.html"
        log "Updated: templates/index.html"
    else
        warn "Could not download index.html"
    fi

    if curl -sSL "${REPO_URL}/dashboard/templates/connections.html" -o "/tmp/connections.html.new" 2>/dev/null; then
        mv "/tmp/connections.html.new" "$dashboard_dir/templates/connections.html"
        log "Updated: templates/connections.html"
    else
        warn "Could not download connections.html"
    fi

    # Restart dashboard service if running
    if systemctl is-active --quiet tortopus-dashboard 2>/dev/null; then
        log "Restarting dashboard service..."
        systemctl restart tortopus-dashboard
        if systemctl is-active --quiet tortopus-dashboard; then
            log "Dashboard restarted successfully"
        else
            warn "Dashboard failed to restart"
        fi
    else
        info "Dashboard service not running (start with: systemctl start tortopus-dashboard)"
    fi
}

#=============================================================================
# Main Upgrade Process
#=============================================================================

main() {
    echo ""
    log "=== Phase 1: Installing Privoxy ==="
    fix_privoxy

    echo ""
    log "=== Phase 2: Updating Squid Configuration ==="
    fix_squid_config

    echo ""
    log "=== Phase 3: Updating Management Scripts ==="
    update_scripts

    echo ""
    log "=== Phase 4: Updating Dashboard ==="
    update_dashboard

    echo ""
    log "=== Phase 5: Verifying Services ==="

    local services_ok=true

    for service in tor privoxy squid; do
        if systemctl is-active --quiet "$service"; then
            info "$service: running"
        else
            warn "$service: not running"
            services_ok=false
        fi
    done

    echo ""
    echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}                    Upgrade Complete!                          ${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
    echo ""

    if [[ "$services_ok" == true ]]; then
        echo -e "${GREEN}All services are running.${NC}"
    else
        echo -e "${YELLOW}Some services may need attention. Check with:${NC}"
        echo "  tortopus-diagnostic"
    fi

    echo ""
    echo "What's new:"
    echo "  - Added Privoxy as HTTP-to-SOCKS bridge for proper Tor routing"
    echo "  - Fixed HTTPS support through the proxy"
    echo "  - Updated management scripts and diagnostic tool"
    echo "  - Dashboard now shows proxy mode (Direct/Tor) with switching buttons"
    echo ""
    echo "Test your proxy:"
    echo "  curl -x http://USER:PASS@127.0.0.1:3128 https://ifconfig.me"
    echo ""
    echo "Switch proxy mode:"
    echo "  tortopus-config --mode tor      # Route through Tor"
    echo "  tortopus-config --mode direct   # Direct connection"
    echo ""
    echo "Dashboard management:"
    echo "  systemctl status tortopus-dashboard   # Check status"
    echo "  systemctl restart tortopus-dashboard  # Restart"
    echo ""
    echo "Run diagnostics:"
    echo "  tortopus-diagnostic"
    echo ""
}

# Run main
main "$@"
