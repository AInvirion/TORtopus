#!/bin/bash
#
# TORtopus Diagnostic Tool
# Comprehensive system health check for TORtopus installation
#

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

PASSED=0
FAILED=0
WARNINGS=0

# Helper functions
print_header() {
    echo -e "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

print_section() {
    echo -e "\n${BLUE}▶ $1${NC}"
}

check_pass() {
    echo -e "  ${GREEN}✓${NC} $1"
    ((PASSED++))
}

check_fail() {
    echo -e "  ${RED}✗${NC} $1"
    ((FAILED++))
}

check_warn() {
    echo -e "  ${YELLOW}⚠${NC} $1"
    ((WARNINGS++))
}

check_info() {
    echo -e "  ${BLUE}ℹ${NC} $1"
}

run_check() {
    local name="$1"
    local command="$2"

    if eval "$command" &>/dev/null; then
        check_pass "$name"
        return 0
    else
        check_fail "$name"
        return 1
    fi
}

# Banner
echo -e "${BLUE}"
cat << "EOF"
╔══════════════════════════════════════════════════════════════╗
║                   TORtopus Diagnostic Tool                   ║
║              System Health & Configuration Check             ║
╚══════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    check_warn "Not running as root - some checks may be limited"
fi

#=============================================================================
# System Information
#=============================================================================
print_header "SYSTEM INFORMATION"

if [[ -f /etc/os-release ]]; then
    source /etc/os-release
    check_info "OS: $PRETTY_NAME"
    check_info "Kernel: $(uname -r)"
fi

check_info "Hostname: $(hostname)"
check_info "Uptime: $(uptime -p 2>/dev/null || uptime)"
check_info "Current User: $(whoami)"

if [[ -n "${SSH_CONNECTION:-}" ]]; then
    local ssh_port=$(echo "$SSH_CONNECTION" | awk '{print $4}')
    check_info "SSH Connection: Port $ssh_port"
fi

#=============================================================================
# Package Checks
#=============================================================================
print_header "INSTALLED PACKAGES"

print_section "Core Security Packages"
run_check "UFW (Firewall)" "command -v ufw"
run_check "fail2ban" "command -v fail2ban-client"
run_check "unattended-upgrades" "dpkg -l | grep -q unattended-upgrades"

print_section "Proxy & Anonymity"
run_check "Tor" "command -v tor"
run_check "Squid" "command -v squid"

print_section "Utilities"
run_check "htdigest (user management)" "command -v htdigest"
run_check "curl (testing)" "command -v curl"

#=============================================================================
# Service Status
#=============================================================================
print_header "SERVICE STATUS"

check_service() {
    local service="$1"
    local name="$2"

    if systemctl is-active --quiet "$service" 2>/dev/null; then
        check_pass "$name is running"

        # Additional status info
        if systemctl is-enabled --quiet "$service" 2>/dev/null; then
            check_info "$name is enabled (starts on boot)"
        else
            check_warn "$name is not enabled for auto-start"
        fi
    else
        check_fail "$name is not running"

        # Try to get error info
        local status=$(systemctl status "$service" 2>&1 | grep "Active:" | head -1)
        if [[ -n "$status" ]]; then
            check_info "Status: $status"
        fi
    fi
}

check_service "sshd" "SSH Server"
check_service "ufw" "UFW Firewall"
check_service "fail2ban" "fail2ban"
check_service "tor" "Tor"
check_service "squid" "Squid Proxy"

#=============================================================================
# Port Checks
#=============================================================================
print_header "LISTENING PORTS"

check_port() {
    local port="$1"
    local name="$2"
    local service="$3"

    if ss -tlnp 2>/dev/null | grep -q ":$port " || netstat -tlnp 2>/dev/null | grep -q ":$port "; then
        check_pass "$name listening on port $port"

        # Show what's listening
        local listener=$(ss -tlnp 2>/dev/null | grep ":$port " | head -1 | grep -oP 'users:\(\(".*?"\)' || echo "")
        if [[ -n "$listener" ]]; then
            check_info "  $listener"
        fi
    else
        check_fail "$name NOT listening on port $port"

        # Check if service is running
        if systemctl is-active --quiet "$service" 2>/dev/null; then
            check_warn "  $service is running but not listening on expected port"
        fi
    fi
}

# Detect SSH port
SSH_PORT=$(ss -tlnp 2>/dev/null | grep sshd | grep -oP '(?<=:)\d+(?= )' | head -1)
SSH_PORT=${SSH_PORT:-22}

check_port "$SSH_PORT" "SSH" "sshd"
check_port "3128" "Squid Proxy" "squid"
check_port "9050" "Tor SOCKS5" "tor"

#=============================================================================
# Firewall Configuration
#=============================================================================
print_header "FIREWALL CONFIGURATION"

if command -v ufw &>/dev/null; then
    if ufw status | grep -q "Status: active"; then
        check_pass "UFW is enabled"

        print_section "Firewall Rules"

        # Check critical rules
        if ufw status | grep -q "$SSH_PORT.*ALLOW"; then
            check_pass "SSH port $SSH_PORT is allowed"
        else
            check_fail "SSH port $SSH_PORT is NOT allowed (potential lockout!)"
        fi

        if ufw status | grep -q "3128.*ALLOW"; then
            check_pass "Squid proxy port 3128 is allowed"
        else
            check_warn "Squid proxy port 3128 is not allowed"
        fi

        if ufw status | grep -q "9050.*ALLOW"; then
            check_pass "Tor SOCKS5 port 9050 is allowed"
        else
            check_warn "Tor SOCKS5 port 9050 is not allowed"
        fi

        # Show default policies
        local default_in=$(ufw status verbose | grep "Default:" | grep -oP "deny \(incoming\)" || echo "")
        local default_out=$(ufw status verbose | grep "Default:" | grep -oP "allow \(outgoing\)" || echo "")

        if [[ -n "$default_in" ]]; then
            check_info "Default incoming: deny (good)"
        else
            check_warn "Default incoming policy is not deny"
        fi

        if [[ -n "$default_out" ]]; then
            check_info "Default outgoing: allow (good)"
        fi

    else
        check_fail "UFW is installed but not enabled"
    fi
else
    check_fail "UFW is not installed"
fi

#=============================================================================
# SSH Configuration
#=============================================================================
print_header "SSH CONFIGURATION"

if [[ -f /etc/ssh/sshd_config ]]; then
    print_section "Security Settings"

    # Check critical settings
    local ssh_port_cfg=$(grep "^Port " /etc/ssh/sshd_config | awk '{print $2}')
    if [[ -n "$ssh_port_cfg" ]]; then
        check_info "Configured SSH port: $ssh_port_cfg"

        if [[ "$ssh_port_cfg" != "$SSH_PORT" ]]; then
            check_warn "Config port ($ssh_port_cfg) != listening port ($SSH_PORT)"
        fi
    fi

    if grep -q "^PasswordAuthentication no" /etc/ssh/sshd_config; then
        check_pass "Password authentication disabled"
    else
        check_warn "Password authentication may be enabled"
    fi

    if grep -q "^PubkeyAuthentication yes" /etc/ssh/sshd_config; then
        check_pass "Public key authentication enabled"
    else
        check_warn "Public key authentication not explicitly enabled"
    fi

    if grep -q "^PermitRootLogin prohibit-password" /etc/ssh/sshd_config; then
        check_pass "Root login restricted to keys only"
    elif grep -q "^PermitRootLogin yes" /etc/ssh/sshd_config; then
        check_warn "Root login with password may be allowed"
    fi

    # Test configuration
    if sshd -t 2>/dev/null; then
        check_pass "SSH configuration is valid"
    else
        check_fail "SSH configuration has errors"
        check_info "Run: sshd -t"
    fi
else
    check_fail "SSH config file not found"
fi

#=============================================================================
# Tor Configuration
#=============================================================================
print_header "TOR CONFIGURATION"

if [[ -f /etc/tor/torrc ]]; then
    print_section "Tor Settings"

    local socks_port=$(grep "^SOCKSPort" /etc/tor/torrc | grep -oP '\d+' | head -1)
    if [[ -n "$socks_port" ]]; then
        check_info "SOCKS port configured: $socks_port"
    fi

    # Check Tor connectivity
    if command -v curl &>/dev/null && systemctl is-active --quiet tor; then
        print_section "Tor Network Connectivity"

        if timeout 15 curl --socks5 127.0.0.1:9050 -s https://check.torproject.org/ 2>/dev/null | grep -q "Congratulations"; then
            check_pass "Connected to Tor network successfully"
        else
            check_warn "Could not verify Tor network connection (may need time to establish circuit)"
        fi
    fi
else
    check_warn "Tor config file not found"
fi

#=============================================================================
# Squid Configuration
#=============================================================================
print_header "SQUID CONFIGURATION"

if [[ -f /etc/squid/squid.conf ]]; then
    print_section "Squid Settings"

    local http_port=$(grep "^http_port" /etc/squid/squid.conf | awk '{print $2}')
    if [[ -n "$http_port" ]]; then
        check_info "HTTP port configured: $http_port"
    fi

    # Check if authentication is configured
    if grep -q "^auth_param digest" /etc/squid/squid.conf; then
        check_pass "Digest authentication configured"
    else
        check_warn "Digest authentication not found in config"
    fi

    # Check password file
    if [[ -f /etc/squid/passwords ]]; then
        local user_count=$(wc -l < /etc/squid/passwords)
        check_pass "Password file exists ($user_count users configured)"
    else
        check_warn "Password file not found at /etc/squid/passwords"
    fi

    # Check Tor integration
    if grep -q "^cache_peer 127.0.0.1 parent 9050" /etc/squid/squid.conf; then
        check_info "Squid configured to route through Tor"
    else
        check_info "Squid in direct mode (not routing through Tor)"
    fi

    # Test Squid config
    if squid -k parse 2>/dev/null; then
        check_pass "Squid configuration is valid"
    else
        check_warn "Squid configuration may have warnings"
    fi
else
    check_fail "Squid config file not found"
fi

#=============================================================================
# fail2ban Status
#=============================================================================
print_header "FAIL2BAN STATUS"

if command -v fail2ban-client &>/dev/null; then
    if systemctl is-active --quiet fail2ban; then
        print_section "Active Jails"

        # List active jails
        local jails=$(fail2ban-client status 2>/dev/null | grep "Jail list:" | cut -d: -f2 | tr ',' '\n')

        if [[ -n "$jails" ]]; then
            for jail in $jails; do
                jail=$(echo "$jail" | xargs) # trim whitespace
                if [[ -n "$jail" ]]; then
                    local banned=$(fail2ban-client status "$jail" 2>/dev/null | grep "Currently banned:" | grep -oP '\d+')
                    local total=$(fail2ban-client status "$jail" 2>/dev/null | grep "Total banned:" | grep -oP '\d+')

                    check_pass "Jail '$jail' active (banned: ${banned:-0}, total: ${total:-0})"
                fi
            done
        else
            check_warn "No active jails found"
        fi
    else
        check_fail "fail2ban is not running"

        # Try to get reason
        check_info "Checking why fail2ban failed..."
        local error=$(journalctl -u fail2ban -n 10 --no-pager 2>/dev/null | grep -i error | tail -1)
        if [[ -n "$error" ]]; then
            check_info "$error"
        fi
    fi
else
    check_warn "fail2ban not installed"
fi

#=============================================================================
# TORtopus Management Scripts
#=============================================================================
print_header "TORTOPUS MANAGEMENT TOOLS"

print_section "Installed Scripts"
run_check "tortopus-user" "[[ -x /usr/local/bin/tortopus-user ]]"
run_check "tortopus-config" "[[ -x /usr/local/bin/tortopus-config ]]"
run_check "tortopus-rollback" "[[ -x /usr/local/bin/tortopus-rollback ]]"
run_check "tortopus-diagnostic" "[[ -x /usr/local/bin/tortopus-diagnostic ]]"

#=============================================================================
# Backup Directory
#=============================================================================
print_header "BACKUP STATUS"

if [[ -d /var/backups/tortopus ]]; then
    local backup_count=$(ls -1 /var/backups/tortopus | wc -l)
    check_pass "Backup directory exists ($backup_count files)"

    print_section "Recent Backups"
    ls -lht /var/backups/tortopus | head -6 | tail -5 | while read line; do
        check_info "$line"
    done
else
    check_warn "Backup directory not found"
fi

#=============================================================================
# Log Files
#=============================================================================
print_header "LOG FILES"

print_section "Recent Errors"

# Check for recent errors in various logs
if [[ -f /var/log/tortopus-install.log ]]; then
    local errors=$(grep -i error /var/log/tortopus-install.log 2>/dev/null | tail -3)
    if [[ -n "$errors" ]]; then
        echo "$errors" | while read line; do
            check_warn "$line"
        done
    else
        check_pass "No errors in installation log"
    fi
fi

# Squid errors
if [[ -f /var/log/squid/cache.log ]]; then
    local squid_errors=$(grep -i "ERROR\|WARNING" /var/log/squid/cache.log 2>/dev/null | tail -3)
    if [[ -n "$squid_errors" ]]; then
        echo "$squid_errors" | while read line; do
            check_warn "Squid: $line"
        done
    fi
fi

# Tor warnings
local tor_warnings=$(journalctl -u tor --no-pager -n 50 2>/dev/null | grep -i "warn\|err" | tail -3)
if [[ -n "$tor_warnings" ]]; then
    echo "$tor_warnings" | while read line; do
        check_warn "Tor: $line"
    done
fi

#=============================================================================
# Network Connectivity
#=============================================================================
print_header "NETWORK CONNECTIVITY"

print_section "External Connectivity Tests"

if command -v curl &>/dev/null; then
    # Test direct internet
    if timeout 5 curl -s https://ifconfig.me >/dev/null 2>&1; then
        check_pass "Direct internet connectivity working"
    else
        check_warn "Direct internet connectivity test failed"
    fi

    # Test DNS
    if timeout 5 curl -s https://google.com >/dev/null 2>&1; then
        check_pass "DNS resolution working"
    else
        check_warn "DNS resolution may have issues"
    fi
else
    check_warn "curl not available for connectivity tests"
fi

#=============================================================================
# Summary
#=============================================================================
print_header "DIAGNOSTIC SUMMARY"

echo ""
echo -e "  ${GREEN}Passed:${NC}   $PASSED"
echo -e "  ${RED}Failed:${NC}   $FAILED"
echo -e "  ${YELLOW}Warnings:${NC} $WARNINGS"
echo ""

if [[ $FAILED -eq 0 ]] && [[ $WARNINGS -eq 0 ]]; then
    echo -e "${GREEN}✓ All checks passed! TORtopus is healthy.${NC}"
    exit 0
elif [[ $FAILED -eq 0 ]]; then
    echo -e "${YELLOW}⚠ Some warnings detected. Review above.${NC}"
    exit 0
else
    echo -e "${RED}✗ Some checks failed. Review above and take corrective action.${NC}"
    echo ""
    echo "Common fixes:"
    echo "  - Service not running: sudo systemctl start <service>"
    echo "  - Service not enabled: sudo systemctl enable <service>"
    echo "  - Configuration errors: Check logs with journalctl -u <service>"
    echo "  - Firewall issues: sudo ufw allow <port>/tcp"
    echo ""
    exit 1
fi
