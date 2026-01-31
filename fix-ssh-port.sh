#!/bin/bash
#
# TORtopus - SSH Port Recovery Script
# Restores SSH to port 22871 after installation bug
#

set -euo pipefail

echo "TORtopus SSH Port Recovery Script"
echo "=================================="
echo ""
echo "This will:"
echo "  1. Change SSH port from 22 to 22871"
echo "  2. Update firewall rules"
echo "  3. Restart SSH service"
echo "  4. Fix fail2ban if needed"
echo ""

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    echo "ERROR: This script must be run as root"
    exit 1
fi

# Backup current config
echo "[1/5] Backing up current SSH config..."
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.before-port-fix

# Change port to 22871
echo "[2/5] Changing SSH port to 22871..."
sed -i 's/^Port 22$/Port 22871/' /etc/ssh/sshd_config

# Verify the change
if grep -q "^Port 22871" /etc/ssh/sshd_config; then
    echo "✓ SSH config updated to port 22871"
else
    echo "✗ Failed to update SSH config"
    exit 1
fi

# Test SSH configuration
echo "[3/5] Testing SSH configuration..."
if sshd -t; then
    echo "✓ SSH configuration is valid"
else
    echo "✗ SSH configuration test failed"
    echo "Restoring backup..."
    cp /etc/ssh/sshd_config.before-port-fix /etc/ssh/sshd_config
    exit 1
fi

# Update firewall
echo "[4/5] Updating firewall rules..."
if command -v ufw &>/dev/null; then
    # Allow new port
    ufw allow 22871/tcp comment 'SSH'

    # Remove old port 22 rule if it exists
    ufw status numbered | grep "22/tcp.*SSH" | awk '{print $1}' | sed 's/\[\|\]//g' | while read rule_num; do
        if [[ -n "$rule_num" ]]; then
            yes | ufw delete "$rule_num" 2>/dev/null || true
        fi
    done

    ufw reload
    echo "✓ Firewall updated"
fi

# Restart SSH
echo "[5/5] Restarting SSH service..."
echo "WARNING: SSH will restart. You may need to reconnect on port 22871"
echo "Press Ctrl+C to cancel, or wait 5 seconds to continue..."
sleep 5

systemctl restart sshd

# Verify SSH is running on correct port
if ss -tlnp | grep -q ":22871.*sshd"; then
    echo "✓ SSH is now listening on port 22871"
else
    echo "✗ WARNING: SSH may not be listening on port 22871"
    echo "Check with: ss -tlnp | grep sshd"
fi

echo ""
echo "=================================="
echo "Recovery Complete!"
echo "=================================="
echo ""
echo "SSH should now be accessible on port 22871"
echo "Test with: ssh -p 22871 root@YOUR_SERVER_IP"
echo ""
echo "Current SSH listening ports:"
ss -tlnp | grep sshd
echo ""
echo "Current firewall rules:"
ufw status numbered | grep SSH
echo ""
