# Usage Guide

Complete guide to using TORtopus proxy and management tools.

## Proxy Modes

TORtopus supports two proxy modes that can be switched at any time.

### Direct Mode

Traffic goes directly through Squid proxy without Tor.

**Characteristics:**
- Faster performance
- Your server's IP address visible
- Lower latency
- Port: 3128 (HTTP)

**Use cases:**
- General browsing
- API testing
- When anonymity is not required

**Switch to Direct Mode:**
```bash
sudo tortopus-config --mode direct
```

### Tor Mode

All traffic routed through the Tor network.

**Characteristics:**
- Enhanced privacy and anonymity
- Tor exit node IP visible (not your server)
- Higher latency (slower)
- Port: 9050 (SOCKS5)

**Use cases:**
- Anonymous browsing
- Privacy-sensitive operations
- Bypassing geographic restrictions
- Security research

**Switch to Tor Mode:**
```bash
sudo tortopus-config --mode tor
```

## Using the Proxy

### HTTP Proxy (Port 3128)

**Environment Variables:**
```bash
export http_proxy="http://username:password@your-server:3128"
export https_proxy="http://username:password@your-server:3128"

# Now all HTTP/HTTPS requests will use the proxy
curl https://ifconfig.me
```

**curl with Proxy:**
```bash
# Recommended: proxy-anyauth (auto-detects auth type)
curl --proxy-anyauth -x 'http://username:password@your-server:3128' https://ifconfig.me

# Explicit basic auth
curl --proxy-basic --proxy-user 'username:password' -x http://your-server:3128 https://ifconfig.me

# Separate credentials
curl -x http://your-server:3128 -U username:password https://ifconfig.me
```

**wget with Proxy:**
```bash
# Using environment variables
export http_proxy="http://username:password@your-server:3128"
wget https://example.com/file.zip

# Or inline
http_proxy="http://username:password@your-server:3128" wget https://example.com/file.zip
```

**Browser Configuration:**

Chrome/Chromium:
```bash
google-chrome --proxy-server="http://your-server:3128" \
  --proxy-auth="username:password"
```

Firefox:
1. Settings → Network Settings → Manual proxy configuration
2. HTTP Proxy: `your-server`, Port: `3128`
3. Check "Use this proxy server for all protocols"
4. Enter credentials when prompted

### SOCKS5 Proxy (Port 9050 - Tor Mode)

**curl with SOCKS5:**
```bash
curl --socks5 your-server:9050 --proxy-user username:password https://check.torproject.org
```

**SSH Tunnel:**
```bash
ssh -D 1080 -C -N root@your-server -p SSH_PORT

# Then configure applications to use localhost:1080 as SOCKS5 proxy
```

**Browser Configuration:**

Firefox:
1. Settings → Network Settings → Manual proxy configuration
2. SOCKS Host: `your-server`, Port: `9050`
3. Check "SOCKS v5"
4. Enter credentials when prompted

## User Management

### Add User

```bash
sudo tortopus-user add alice
# Enter password when prompted (alphanumeric only, 8+ chars)
```

### Remove User

```bash
sudo tortopus-user remove alice
```

### List Users

```bash
sudo tortopus-user list
```

### Change Password

```bash
sudo tortopus-user passwd alice
# Enter new password when prompted
```

## Management Commands

### Check System Status

```bash
sudo tortopus-diagnostic
```

Shows:
- System information and resources
- Service status (Squid, Tor, fail2ban, UFW)
- Port checks
- Firewall configuration
- SSH security settings
- Proxy users
- Tor network connectivity
- Recent errors and warnings
- Actionable recommendations

### Rollback Configuration

```bash
sudo tortopus-rollback
```

Restores all original configurations from backups.

### View Logs

**Squid Access Log:**
```bash
sudo tail -f /var/log/squid/access.log
```

**Squid Cache Log (errors):**
```bash
sudo tail -f /var/log/squid/cache.log
```

**Tor Log:**
```bash
sudo journalctl -u tor -f
```

**fail2ban Status:**
```bash
sudo fail2ban-client status
sudo fail2ban-client status sshd
sudo fail2ban-client status squid
```

**Installation Log:**
```bash
tail -100 /var/log/tortopus/install.log
```

## Testing

### Test Direct Connectivity

```bash
# Check your IP through the proxy
curl --proxy-anyauth -x 'http://username:password@your-server:3128' https://ifconfig.me

# Should show your server's IP
```

### Test Tor Connectivity

```bash
# Switch to Tor mode
sudo tortopus-config --mode tor

# Check if using Tor
curl --proxy-anyauth -x 'http://username:password@your-server:3128' https://check.torproject.org

# Should show "Congratulations. This browser is configured to use Tor."
```

### Test Authentication

```bash
# Wrong password should fail
curl --proxy-anyauth -x 'http://username:wrongpass@your-server:3128' https://ifconfig.me
# Returns 407 Proxy Authentication Required

# Correct password should work
curl --proxy-anyauth -x 'http://username:correctpass@your-server:3128' https://ifconfig.me
# Returns your IP
```

## Service Management

### Restart Services

```bash
# Restart Squid
sudo systemctl restart squid

# Restart Tor
sudo systemctl restart tor

# Restart fail2ban
sudo systemctl restart fail2ban
```

### Check Service Status

```bash
sudo systemctl status squid tor fail2ban
```

### Enable/Disable Services

```bash
# Disable service
sudo systemctl stop squid
sudo systemctl disable squid

# Enable service
sudo systemctl enable squid
sudo systemctl start squid
```

## Password Requirements

All proxy user passwords must:
- Be at least 8 characters long
- Contain only letters and numbers (alphanumeric)
- No special characters (no `!@#$%^&*()` etc.)

This ensures compatibility with HTTP Basic Authentication and URL encoding.

## Performance Tips

### Direct Mode
- Use for maximum speed
- No additional encryption overhead
- Lowest latency

### Tor Mode
- Expect 2-5x slower speeds
- Best for privacy-sensitive operations
- Circuit changes every 10 minutes (new IP)

## Security Best Practices

1. **Use strong passwords**: Even though alphanumeric only, use 12+ characters
2. **Rotate passwords regularly**: Change user passwords periodically
3. **Monitor access logs**: Check for suspicious activity
4. **Keep system updated**: Automatic updates are enabled
5. **Review fail2ban**: Check banned IPs regularly
6. **Limit user accounts**: Only create accounts for trusted users

## API/Programming Usage

### Python with requests

```python
import requests

proxies = {
    'http': 'http://username:password@your-server:3128',
    'https': 'http://username:password@your-server:3128',
}

response = requests.get('https://ifconfig.me', proxies=proxies)
print(response.text)
```

### Python with SOCKS5 (Tor mode)

```python
import requests

proxies = {
    'http': 'socks5://username:password@your-server:9050',
    'https': 'socks5://username:password@your-server:9050',
}

response = requests.get('https://check.torproject.org', proxies=proxies)
print(response.text)
```

### Node.js

```javascript
const axios = require('axios');

axios.get('https://ifconfig.me', {
    proxy: {
        protocol: 'http',
        host: 'your-server',
        port: 3128,
        auth: {
            username: 'username',
            password: 'password'
        }
    }
}).then(response => console.log(response.data));
```
