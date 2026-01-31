# Configuration

Detailed configuration reference for TORtopus.

## Configuration Files

### SSH Configuration

**Location:** `/etc/ssh/sshd_config`

Key settings applied by TORtopus:
```
Port <your-selected-port>
PermitRootLogin prohibit-password
PubkeyAuthentication yes
PasswordAuthentication no
ChallengeResponseAuthentication no
X11Forwarding no
```

**Strong Cryptography:**
- KEX Algorithms: curve25519-sha256, diffie-hellman-group16-sha512
- Ciphers: chacha20-poly1305, aes256-gcm, aes128-gcm
- MACs: hmac-sha2-512-etm, hmac-sha2-256-etm

**Connection Settings:**
- ClientAliveInterval: 300 seconds
- MaxAuthTries: 3
- LoginGraceTime: 60 seconds

**Backup:** `/var/backups/tortopus/sshd_config.backup.*`

### Squid Configuration

**Location:** `/etc/squid/squid.conf`

**Basic Settings:**
```
http_port 3128
```

**Authentication:**
```
auth_param basic program /usr/lib/squid/basic_ncsa_auth /etc/squid/passwords
auth_param basic realm TORtopus Proxy
acl authenticated proxy_auth REQUIRED
http_access allow authenticated
```

**Direct Mode Configuration:**
```
# Standard proxy mode
http_access allow authenticated
```

**Tor Mode Configuration:**
```
# Route through Tor
cache_peer 127.0.0.1 parent 9050 0 no-query no-digest proxy-only
never_direct allow all
```

**Access Logging:**
```
access_log /var/log/squid/access.log squid
cache_log /var/log/squid/cache.log
```

**Backup:** `/var/backups/tortopus/squid.conf.backup.*`

### Tor Configuration

**Location:** `/etc/tor/torrc`

```
# SOCKS proxy (localhost only)
SOCKSPort 127.0.0.1:9050

# Control port
ControlPort 9051

# Logging
Log notice file /var/log/tor/notices.log

# Performance
NumEntryGuards 8
CircuitBuildTimeout 30

# Security
CookieAuthentication 1
DataDirectory /var/lib/tor
```

**Backup:** `/var/backups/tortopus/torrc.backup.*`

### UFW Firewall

**Location:** `/etc/ufw/user.rules`

**Default Policies:**
```
Default incoming: deny
Default outgoing: allow
```

**Allowed Ports:**
- SSH: Your configured port (22 or custom)
- Squid: 3128/tcp
- Tor: 9050/tcp

**View Rules:**
```bash
sudo ufw status verbose
sudo ufw status numbered
```

**Backup:** `/var/backups/tortopus/user.rules.backup.*`

### fail2ban Configuration

**Location:** `/etc/fail2ban/jail.local`

**SSH Jail:**
```
[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 7200    # 2 hours
findtime = 600    # 10 minutes
```

**Squid Jail:**
```
[squid]
enabled = true
port = 3128
filter = squid
logpath = /var/log/squid/access.log
maxretry = 10
bantime = 3600    # 1 hour
findtime = 600    # 10 minutes
```

**Squid Filter:** `/etc/fail2ban/filter.d/squid.conf`
```
[Definition]
failregex = ^.*TCP_DENIED/407.*<HOST>.*$
ignoreregex =
```

**Backup:** `/var/backups/tortopus/jail.local.backup.*`

### User Passwords

**Location:** `/etc/squid/passwords`

Format: htpasswd file (username:hashed_password)

**Permissions:**
- Owner: root:proxy
- Mode: 640

**Management:**
```bash
# Add user
sudo htpasswd -b /etc/squid/passwords username password

# Remove user
sudo htpasswd -D /etc/squid/passwords username

# Change password
sudo htpasswd -b /etc/squid/passwords username newpassword
```

## Customization

### Change SSH Port

```bash
# Edit SSH config
sudo nano /etc/ssh/sshd_config
# Change: Port 2222

# Update firewall
sudo ufw delete allow <old-port>/tcp
sudo ufw allow 2222/tcp

# Restart SSH
sudo systemctl restart sshd
```

### Change Proxy Port

```bash
# Edit Squid config
sudo nano /etc/squid/squid.conf
# Change: http_port 3128

# Update firewall
sudo ufw delete allow 3128/tcp
sudo ufw allow <new-port>/tcp

# Restart Squid
sudo systemctl restart squid
```

### Adjust fail2ban Sensitivity

```bash
# Edit jail config
sudo nano /etc/fail2ban/jail.local

# Modify values:
# maxretry = 5     # Number of attempts before ban
# bantime = 3600   # Ban duration in seconds
# findtime = 600   # Time window for counting attempts

# Restart fail2ban
sudo systemctl restart fail2ban
```

### Configure Tor Exit Nodes

```bash
# Edit Tor config
sudo nano /etc/tor/torrc

# Add country codes (exit through specific countries)
ExitNodes {us},{gb},{de}
StrictNodes 1

# Or exclude countries
ExcludeNodes {cn},{ru}
StrictNodes 1

# Restart Tor
sudo systemctl restart tor
```

### Enable Squid Cache (Advanced)

By default, Squid caching is disabled. To enable:

```bash
# Edit Squid config
sudo nano /etc/squid/squid.conf

# Add cache settings
cache_dir ufs /var/spool/squid 100 16 256
maximum_object_size 4 MB
cache_mem 256 MB

# Initialize cache
sudo squid -z

# Restart Squid
sudo systemctl restart squid
```

## Environment Variables

TORtopus installer uses these variables (set automatically):

```bash
BACKUP_DIR=/var/backups/tortopus
INSTALL_LOG=/var/log/tortopus/install.log
BIN_DIR=/usr/local/bin
SQUID_USERS_FILE=/etc/squid/passwords
SSH_PORT=<detected-or-selected-port>
```

## Backup and Restore

### Manual Backup

```bash
# Create backup directory
mkdir -p /root/tortopus-backup

# Backup configurations
cp /etc/ssh/sshd_config /root/tortopus-backup/
cp /etc/squid/squid.conf /root/tortopus-backup/
cp /etc/squid/passwords /root/tortopus-backup/
cp /etc/tor/torrc /root/tortopus-backup/
cp /etc/fail2ban/jail.local /root/tortopus-backup/
```

### Restore from Backup

```bash
# Using tortopus-rollback
sudo tortopus-rollback

# Manual restore
cp /var/backups/tortopus/sshd_config.backup.* /etc/ssh/sshd_config
cp /var/backups/tortopus/squid.conf.backup.* /etc/squid/squid.conf
# ... etc

# Restart services
sudo systemctl restart sshd squid tor fail2ban
```

## Log Files

| Service | Log Location | Purpose |
|---------|-------------|---------|
| TORtopus Installer | `/var/log/tortopus/install.log` | Installation progress and errors |
| SSH | `/var/log/auth.log` | SSH connections and authentication |
| Squid Access | `/var/log/squid/access.log` | Proxy requests and responses |
| Squid Cache | `/var/log/squid/cache.log` | Squid errors and warnings |
| Tor | `journalctl -u tor` | Tor network status and errors |
| fail2ban | `journalctl -u fail2ban` | Ban events and monitoring |
| UFW | `/var/log/ufw.log` | Firewall events |

## Performance Tuning

### Squid Performance

```bash
# Edit Squid config
sudo nano /etc/squid/squid.conf

# Add performance settings
dns_nameservers 8.8.8.8 8.8.4.4
workers 4
client_lifetime 1 hour
half_closed_clients off
```

### Tor Performance

```bash
# Edit Tor config
sudo nano /etc/tor/torrc

# Increase entry guards for stability
NumEntryGuards 8

# Reduce circuit build timeout for faster connections
CircuitBuildTimeout 20
```

## Security Hardening

### Additional SSH Hardening

```bash
# Edit SSH config
sudo nano /etc/ssh/sshd_config

# Add restrictions
AllowUsers root admin
MaxStartups 2:30:10
LoginGraceTime 30
```

### Restrict Squid Access by IP

```bash
# Edit Squid config
sudo nano /etc/squid/squid.conf

# Add ACL for allowed IPs
acl allowed_ips src 203.0.113.0/24
http_access allow allowed_ips authenticated
```

### Enable Squid SSL Bump (HTTPS Inspection)

**WARNING:** This requires SSL certificate and can break some sites.

```bash
# Generate SSL certificate
openssl req -new -newkey rsa:2048 -days 365 -nodes -x509 \
  -keyout /etc/squid/squid.pem -out /etc/squid/squid.pem

# Edit Squid config
sudo nano /etc/squid/squid.conf

# Add SSL bump settings
http_port 3128 ssl-bump cert=/etc/squid/squid.pem
ssl_bump server-first all
sslcrtd_program /usr/lib/squid/security_file_certgen -s /var/lib/ssl_db -M 4MB
```
