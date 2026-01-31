# Troubleshooting

Common issues and solutions for TORtopus.

## Diagnostic Tool

Always start troubleshooting with the diagnostic tool:

```bash
sudo tortopus-diagnostic
```

This will check:
- System status and resources
- Service health (Squid, Tor, fail2ban, UFW)
- Port availability
- Firewall configuration
- SSH security
- Proxy users and functionality
- Common misconfigurations

The tool provides actionable recommendations for fixing issues.

## SSH Issues

### Can't Connect After Installation

**Symptoms:** SSH connection refused or times out after running installer.

**Causes:**
1. SSH port changed but firewall not updated
2. SSH service failed to restart
3. Wrong port used in connection

**Solutions:**

```bash
# If you have console access:
# Check SSH status
sudo systemctl status sshd

# Check which port SSH is listening on
sudo ss -tlnp | grep sshd

# Check firewall rules
sudo ufw status numbered

# If port mismatch, fix firewall
sudo ufw allow <correct-ssh-port>/tcp
sudo ufw reload

# Restart SSH
sudo systemctl restart sshd
```

### SSH Key Authentication Not Working

**Symptoms:** Still prompted for password after SSH hardening.

**Causes:**
1. Public key not in authorized_keys
2. Wrong permissions on .ssh directory
3. SSH config not reloaded

**Solutions:**

```bash
# Check authorized_keys exists and has your key
cat ~/.ssh/authorized_keys

# Fix permissions
chmod 700 ~/.ssh
chmod 600 ~/.ssh/authorized_keys

# Add your key if missing
echo "your-public-key" >> ~/.ssh/authorized_keys

# Restart SSH
sudo systemctl restart sshd
```

### Locked Out of Server

**Symptoms:** Cannot connect via SSH at all.

**Solutions:**

```bash
# Use hosting provider's console/recovery mode

# Check if SSH is running
sudo systemctl status sshd

# Disable firewall temporarily
sudo ufw disable

# Check SSH config for errors
sudo sshd -t

# Restore SSH backup if needed
sudo cp /var/backups/tortopus/sshd_config.backup.* /etc/ssh/sshd_config
sudo systemctl restart sshd

# Re-enable firewall after fixing
sudo ufw enable
```

## Proxy Issues

### 407 Proxy Authentication Required

**Symptoms:** Proxy returns 407 error even with correct credentials.

**Causes:**
1. Wrong username or password
2. Special characters in password
3. Authentication not configured
4. URL encoding issues

**Solutions:**

```bash
# Verify user exists
sudo cat /etc/squid/passwords | grep username

# Check Squid authentication config
sudo grep "auth_param" /etc/squid/squid.conf

# Ensure basic auth is configured
# Should see: auth_param basic program /usr/lib/squid/basic_ncsa_auth /etc/squid/passwords

# Test with simple password (alphanumeric only)
sudo tortopus-user passwd username
# Enter simple password like: testpass123

# Try connection
curl --proxy-anyauth -x 'http://username:testpass123@server:3128' https://ifconfig.me

# Reload Squid
sudo systemctl reload squid
```

### Proxy Not Responding

**Symptoms:** Connection timeout or refused when connecting to proxy.

**Causes:**
1. Squid not running
2. Firewall blocking port 3128
3. Squid configuration error

**Solutions:**

```bash
# Check Squid status
sudo systemctl status squid

# If not running, check logs
sudo journalctl -u squid -n 50

# Test Squid config
sudo squid -k parse

# Check firewall
sudo ufw status | grep 3128

# If not allowed, add rule
sudo ufw allow 3128/tcp

# Restart Squid
sudo systemctl restart squid

# Test locally
curl -x http://127.0.0.1:3128 https://ifconfig.me
```

### Squid Won't Start

**Symptoms:** Squid service fails to start.

**Causes:**
1. Configuration syntax error
2. Port already in use
3. Missing password file
4. Permission issues

**Solutions:**

```bash
# Check Squid logs
sudo journalctl -u squid -n 50
sudo tail -50 /var/log/squid/cache.log

# Test configuration
sudo squid -k parse

# Check if port is in use
sudo ss -tlnp | grep 3128

# Ensure password file exists
sudo ls -la /etc/squid/passwords

# If missing, create it
sudo touch /etc/squid/passwords
sudo chown root:proxy /etc/squid/passwords
sudo chmod 640 /etc/squid/passwords

# Fix permissions
sudo chown -R proxy:proxy /var/spool/squid
sudo chown -R proxy:proxy /var/log/squid

# Try starting again
sudo systemctl start squid
```

## Tor Issues

### Tor Not Connecting to Network

**Symptoms:** Tor service running but can't access Tor network.

**Causes:**
1. Firewall blocking Tor
2. Network restrictions
3. Tor consensus issues

**Solutions:**

```bash
# Check Tor logs
sudo journalctl -u tor -n 100

# Look for errors about:
# - "Failed to find node for hop"
# - "TLS error"
# - "Directory fetch failed"

# Test Tor connectivity
curl --socks5 127.0.0.1:9050 https://check.torproject.org

# Restart Tor
sudo systemctl restart tor

# Wait 30 seconds for circuit establishment
sleep 30

# Try again
curl --socks5 127.0.0.1:9050 https://check.torproject.org
```

### Tor Won't Start

**Symptoms:** Tor service fails to start.

**Causes:**
1. Port 9050 already in use
2. Configuration error
3. Permission issues

**Solutions:**

```bash
# Check Tor logs
sudo journalctl -u tor -n 50

# Test Tor config
sudo -u debian-tor tor --verify-config

# Check if port in use
sudo ss -tlnp | grep 9050

# Check permissions
sudo ls -la /var/lib/tor
sudo chown -R debian-tor:debian-tor /var/lib/tor

# Restart Tor
sudo systemctl restart tor
```

### Proxy Not Routing Through Tor

**Symptoms:** In Tor mode but seeing regular IP instead of Tor exit.

**Causes:**
1. Squid not configured for Tor mode
2. Tor not running
3. Cache peer configuration missing

**Solutions:**

```bash
# Verify Tor mode is enabled
sudo grep "cache_peer.*9050" /etc/squid/squid.conf

# If not found, switch to Tor mode
sudo tortopus-config --mode tor

# Verify Tor is running
sudo systemctl status tor

# Test Tor directly
curl --socks5 127.0.0.1:9050 https://ifconfig.me

# Restart Squid
sudo systemctl restart squid

# Test proxy
curl --proxy-anyauth -x 'http://user:pass@server:3128' https://check.torproject.org
```

## fail2ban Issues

### fail2ban Not Starting

**Symptoms:** fail2ban service fails to start.

**Causes:**
1. Log file doesn't exist
2. Configuration error
3. Filter errors

**Solutions:**

```bash
# Check fail2ban logs
sudo journalctl -u fail2ban -n 50

# Common issue: Squid log doesn't exist
sudo mkdir -p /var/log/squid
sudo touch /var/log/squid/access.log
sudo chown proxy:proxy /var/log/squid/access.log

# Test configuration
sudo fail2ban-client -t

# Restart fail2ban
sudo systemctl restart fail2ban

# Check status
sudo fail2ban-client status
```

### fail2ban Not Banning

**Symptoms:** Repeated failed attempts not resulting in bans.

**Causes:**
1. Jail not enabled
2. Maxretry set too high
3. Filter not matching logs

**Solutions:**

```bash
# Check active jails
sudo fail2ban-client status

# Check specific jail
sudo fail2ban-client status sshd
sudo fail2ban-client status squid

# Test filter manually
sudo fail2ban-regex /var/log/squid/access.log /etc/fail2ban/filter.d/squid.conf

# View banned IPs
sudo fail2ban-client status sshd

# Manually ban IP (for testing)
sudo fail2ban-client set sshd banip 1.2.3.4

# Unban IP
sudo fail2ban-client set sshd unbanip 1.2.3.4
```

## Firewall Issues

### Firewall Blocking Legitimate Traffic

**Symptoms:** Services work locally but not remotely.

**Causes:**
1. Port not allowed in firewall
2. Wrong port configured
3. Firewall rules incorrect

**Solutions:**

```bash
# Check current rules
sudo ufw status verbose
sudo ufw status numbered

# Allow required ports
sudo ufw allow <ssh-port>/tcp
sudo ufw allow 3128/tcp
sudo ufw allow 9050/tcp

# Delete wrong rules
sudo ufw delete <rule-number>

# Reload firewall
sudo ufw reload

# Test from remote
nc -zv your-server 3128
```

### Can't Disable Firewall

**Symptoms:** Need to disable UFW but command fails.

**Solutions:**

```bash
# Force disable
sudo ufw --force disable

# Check status
sudo ufw status

# If needed, reset completely
sudo ufw --force reset
```

## Performance Issues

### Slow Proxy Speed

**Symptoms:** Proxy works but very slow.

**Causes:**
1. Tor mode enabled (inherently slower)
2. DNS resolution slow
3. Squid cache not configured

**Solutions:**

```bash
# Check if in Tor mode
sudo grep "cache_peer.*9050" /etc/squid/squid.conf

# Switch to direct mode for speed
sudo tortopus-config --mode direct

# Add fast DNS servers to Squid
sudo nano /etc/squid/squid.conf
# Add: dns_nameservers 8.8.8.8 8.8.4.4

# Restart Squid
sudo systemctl restart squid
```

### High CPU Usage

**Symptoms:** Server CPU constantly high.

**Causes:**
1. Tor circuit building
2. Excessive logging
3. Attack/abuse

**Solutions:**

```bash
# Check what's using CPU
top
htop

# Check Squid access log for abuse
sudo tail -100 /var/log/squid/access.log

# Reduce Squid logging
sudo nano /etc/squid/squid.conf
# Comment out: #access_log /var/log/squid/access.log

# Check fail2ban bans
sudo fail2ban-client status squid

# Restart services
sudo systemctl restart squid
```

## Password Issues

### Special Characters in Password Not Working

**Symptoms:** Password with `!@#$%` fails authentication.

**Cause:** TORtopus only supports alphanumeric passwords.

**Solution:**

```bash
# Reset password to alphanumeric only
sudo tortopus-user passwd username
# Enter password with only letters and numbers (8+ chars)

# Examples of valid passwords:
# Abc123xyz789
# MyPassword2024
# SecurePass999

# Examples of INVALID passwords:
# Abc123!@# (has special chars)
# Pass$word (has special char)
```

### Forgot Dashboard Password

**Symptoms:** Can't log into web dashboard.

**Solution:**

```bash
# Reset dashboard password
sudo nano /opt/tortopus-dashboard/app.py

# Find and change:
DASHBOARD_PASSWORD = 'new-password-here'

# Restart dashboard
sudo systemctl restart tortopus-dashboard
```

## Installation Issues

### Installation Fails Midway

**Symptoms:** Installer stops with error.

**Solutions:**

```bash
# Check installation log
sudo tail -100 /var/log/tortopus/install.log

# Common issues:
# 1. Network timeout
sudo apt-get update
sudo apt-get install -y tor squid fail2ban

# 2. Service failed to start
sudo systemctl status squid tor fail2ban

# 3. Fix specific service and re-run installer
sudo ./install.sh
```

### Rollback Doesn't Work

**Symptoms:** tortopus-rollback command fails.

**Solutions:**

```bash
# Check if backups exist
ls -la /var/backups/tortopus/

# Manually restore critical files
sudo cp /var/backups/tortopus/sshd_config.backup.* /etc/ssh/sshd_config
sudo cp /var/backups/tortopus/squid.conf.backup.* /etc/squid/squid.conf

# Restart services
sudo systemctl restart sshd squid tor fail2ban
```

## Getting Help

If issues persist:

1. Run diagnostic: `sudo tortopus-diagnostic`
2. Collect logs:
   ```bash
   sudo journalctl -u squid -n 100 > squid.log
   sudo journalctl -u tor -n 100 > tor.log
   sudo journalctl -u fail2ban -n 100 > fail2ban.log
   sudo tail -200 /var/log/tortopus/install.log > install.log
   ```
3. Check firewall: `sudo ufw status verbose > firewall.txt`
4. Open issue: https://github.com/AInvirion/TORtopus/issues

Include:
- Diagnostic output
- Relevant log files
- Ubuntu version: `lsb_release -a`
- Error messages
- Steps to reproduce
