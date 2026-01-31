#!/bin/bash
#
# TORtopus Verification Script
# Verifies that TORtopus installation is working correctly
#

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASSED=0
FAILED=0

check() {
    local name="$1"
    local command="$2"

    printf "%-50s " "$name"

    if eval "$command" &>/dev/null; then
        echo -e "${GREEN}[PASS]${NC}"
        ((PASSED++))
        return 0
    else
        echo -e "${RED}[FAIL]${NC}"
        ((FAILED++))
        return 1
    fi
}

check_service() {
    local name="$1"
    local service="$2"

    printf "%-50s " "$name"

    if systemctl is-active --quiet "$service"; then
        echo -e "${GREEN}[PASS]${NC}"
        ((PASSED++))
        return 0
    else
        echo -e "${RED}[FAIL]${NC}"
        ((FAILED++))
        return 1
    fi
}

check_port() {
    local name="$1"
    local port="$2"

    printf "%-50s " "$name"

    if netstat -tuln 2>/dev/null | grep -q ":$port " || ss -tuln 2>/dev/null | grep -q ":$port "; then
        echo -e "${GREEN}[PASS]${NC}"
        ((PASSED++))
        return 0
    else
        echo -e "${RED}[FAIL]${NC}"
        ((FAILED++))
        return 1
    fi
}

echo "======================================"
echo "TORtopus Installation Verification"
echo "======================================"
echo ""

# Check system basics
echo "System Checks:"
check "Operating System" "[[ -f /etc/os-release ]]"
check "Root privileges" "[[ \$EUID -eq 0 ]]"
echo ""

# Check installed packages
echo "Package Checks:"
check "UFW installed" "command -v ufw"
check "fail2ban installed" "command -v fail2ban-client"
check "Tor installed" "command -v tor"
check "Squid installed" "command -v squid"
check "htdigest installed" "command -v htdigest"
echo ""

# Check services
echo "Service Status:"
check_service "SSH service" "sshd"
check_service "UFW service" "ufw"
check_service "fail2ban service" "fail2ban"
check_service "Tor service" "tor"
check_service "Squid service" "squid"
echo ""

# Check ports
echo "Port Checks:"
check_port "SSH port 22" "22"
check_port "Squid port 3128" "3128"
check_port "Tor SOCKS port 9050" "9050"
echo ""

# Check configurations
echo "Configuration Checks:"
check "SSH config exists" "[[ -f /etc/ssh/sshd_config ]]"
check "Squid config exists" "[[ -f /etc/squid/squid.conf ]]"
check "Tor config exists" "[[ -f /etc/tor/torrc ]]"
check "Password auth disabled in SSH" "grep -q '^PasswordAuthentication no' /etc/ssh/sshd_config"
check "Backup directory exists" "[[ -d /var/backups/tortopus ]]"
echo ""

# Check management scripts
echo "Management Scripts:"
check "tortopus-user script" "[[ -x /usr/local/bin/tortopus-user ]]"
check "tortopus-config script" "[[ -x /usr/local/bin/tortopus-config ]]"
check "tortopus-rollback script" "[[ -x /usr/local/bin/tortopus-rollback ]]"
echo ""

# Check firewall rules
echo "Firewall Rules:"
check "UFW enabled" "ufw status | grep -q 'Status: active'"
check "SSH allowed" "ufw status | grep -q '22.*ALLOW'"
check "Squid allowed" "ufw status | grep -q '3128.*ALLOW'"
check "Tor allowed" "ufw status | grep -q '9050.*ALLOW'"
echo ""

# Check Tor connectivity
echo "Tor Connectivity:"
if command -v curl &>/dev/null; then
    printf "%-50s " "Tor network connection"
    if timeout 10 curl --socks5 127.0.0.1:9050 -s https://check.torproject.org/ | grep -q "Congratulations"; then
        echo -e "${GREEN}[PASS]${NC}"
        ((PASSED++))
    else
        echo -e "${YELLOW}[WARN]${NC} (May take time to establish circuit)"
    fi
fi
echo ""

# Summary
echo "======================================"
echo "Summary:"
echo "  Passed: $PASSED"
echo "  Failed: $FAILED"
echo "======================================"
echo ""

if [[ $FAILED -eq 0 ]]; then
    echo -e "${GREEN}All checks passed! TORtopus is properly installed.${NC}"
    exit 0
else
    echo -e "${RED}Some checks failed. Review the output above.${NC}"
    exit 1
fi
