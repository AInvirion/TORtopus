#!/bin/bash
#
# TORtopus Dashboard Installer
# Installs the web management dashboard
#

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

DASHBOARD_DIR="/opt/tortopus-dashboard"
SERVICE_FILE="/etc/systemd/system/tortopus-dashboard.service"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*"
}

error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

# Check root
if [[ $EUID -ne 0 ]]; then
    error "This script must be run as root"
    exit 1
fi

log "Installing TORtopus Dashboard..."

# Install Python and dependencies
log "Installing Python dependencies..."
apt-get update -qq
apt-get install -y -qq python3 python3-pip

# Create dashboard directory
log "Creating dashboard directory..."
mkdir -p "$DASHBOARD_DIR"

# Copy dashboard files
log "Copying dashboard files..."
if [[ -d "$SCRIPT_DIR/dashboard" ]]; then
    cp -r "$SCRIPT_DIR/dashboard/"* "$DASHBOARD_DIR/"
else
    error "Dashboard directory not found"
    exit 1
fi

# Install Python requirements
log "Installing Flask..."
cd "$DASHBOARD_DIR"
pip3 install -q -r requirements.txt

# Set dashboard password
info "Setting dashboard password..."
read -s -p "Enter dashboard admin password (default: changeme123): " dash_password
echo

if [[ -n "$dash_password" ]]; then
    sed -i "s/DASHBOARD_PASSWORD = 'changeme123'/DASHBOARD_PASSWORD = '$dash_password'/" "$DASHBOARD_DIR/app.py"
    log "Dashboard password set"
else
    echo -e "${YELLOW}Warning: Using default password 'changeme123' - CHANGE THIS!${NC}"
fi

# Install systemd service
log "Installing systemd service..."
cp "$DASHBOARD_DIR/tortopus-dashboard.service" "$SERVICE_FILE"
systemctl daemon-reload
systemctl enable tortopus-dashboard
systemctl start tortopus-dashboard

# Wait for service to start
sleep 2

if systemctl is-active --quiet tortopus-dashboard; then
    log "Dashboard installed and running!"
    echo ""
    echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}   TORtopus Dashboard Installed Successfully!${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
    echo ""
    echo "Access the dashboard:"
    echo ""
    echo "1. Via SSH Tunnel (Recommended):"
    echo "   ssh -L 5000:127.0.0.1:5000 root@YOUR_SERVER -p SSH_PORT"
    echo "   Then open: http://localhost:5000"
    echo ""
    echo "2. Local access:"
    echo "   http://127.0.0.1:5000"
    echo ""
    echo "Default credentials:"
    echo "   Username: admin"
    if [[ -n "$dash_password" ]]; then
        echo "   Password: (your custom password)"
    else
        echo "   Password: changeme123"
    fi
    echo ""
    echo "Service management:"
    echo "   Status:  systemctl status tortopus-dashboard"
    echo "   Restart: systemctl restart tortopus-dashboard"
    echo "   Logs:    journalctl -u tortopus-dashboard -f"
    echo ""
else
    error "Dashboard failed to start"
    echo "Check logs: journalctl -u tortopus-dashboard -n 50"
    exit 1
fi
