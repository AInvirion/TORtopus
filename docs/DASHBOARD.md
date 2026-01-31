# Web Dashboard

TORtopus includes an optional web-based dashboard for easy user management.

## Features

- Add and remove proxy users
- Change user passwords
- View system status (Squid, Tor, fail2ban, UFW)
- No database required (file-based)
- HTTP Basic Authentication
- Clean, modern UI
- Runs as systemd service

## Installation

### Automatic Installation

```bash
# Run dashboard installer
sudo ./install-dashboard.sh
```

The installer will:
1. Install Python and Flask dependencies
2. Copy dashboard files to `/opt/tortopus-dashboard`
3. Prompt for admin password
4. Install and start systemd service

### Manual Installation

```bash
# Install dependencies
sudo apt-get update
sudo apt-get install -y python3 python3-pip

# Create installation directory
sudo mkdir -p /opt/tortopus-dashboard
sudo cp -r dashboard/* /opt/tortopus-dashboard/

# Install Python dependencies
cd /opt/tortopus-dashboard
sudo pip3 install -r requirements.txt

# Set dashboard password
sudo nano /opt/tortopus-dashboard/app.py
# Change: DASHBOARD_PASSWORD = 'your-strong-password'

# Install systemd service
sudo cp tortopus-dashboard.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable tortopus-dashboard
sudo systemctl start tortopus-dashboard
```

## Access

### Via SSH Tunnel (Recommended)

Most secure method - no ports exposed to internet:

```bash
# From your local machine
ssh -L 5000:127.0.0.1:5000 root@your-server -p SSH_PORT

# Open browser
http://localhost:5000
```

**Default credentials:**
- Username: `admin`
- Password: `changeme123` (or your custom password)

### Via nginx Reverse Proxy with SSL

For production use with HTTPS:

```bash
# Install nginx
sudo apt-get install -y nginx certbot python3-certbot-nginx

# Configure nginx
sudo nano /etc/nginx/sites-available/tortopus-dashboard
```

Add configuration:
```nginx
server {
    listen 8443 ssl;
    server_name your-domain.com;

    ssl_certificate /etc/ssl/certs/tortopus.crt;
    ssl_certificate_key /etc/ssl/private/tortopus.key;

    location / {
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}
```

Enable site:
```bash
# Enable site
sudo ln -s /etc/nginx/sites-available/tortopus-dashboard /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl restart nginx

# Allow port in firewall
sudo ufw allow 8443/tcp
```

Access at: `https://your-server:8443`

## Usage

### Dashboard Interface

**System Status Card:**
- Squid Proxy status
- Tor Network status
- fail2ban status
- UFW Firewall status
- Total user count
- Last updated timestamp

**Add New User:**
- Enter username (alphanumeric and underscore only)
- Enter password (alphanumeric only, min 8 characters)
- Click "Add User"

**User List:**
- View all configured users
- Change password button
- Delete user button

### Managing Users

**Add User:**
1. Enter username in "Add New User" section
2. Enter password (alphanumeric, 8+ chars)
3. Click "Add User"
4. User is immediately available for proxy authentication

**Change Password:**
1. Click "Change Password" button next to user
2. Enter new password in prompt (alphanumeric, 8+ chars)
3. Click OK
4. Password is updated immediately

**Delete User:**
1. Click "Delete" button next to user
2. Confirm deletion
3. User is removed immediately

## API Endpoints

The dashboard provides REST API endpoints:

### Get System Status

```bash
curl -u admin:password http://127.0.0.1:5000/api/status
```

Response:
```json
{
  "squid": "active",
  "tor": "active",
  "fail2ban": "active",
  "ufw": "active",
  "user_count": 3,
  "timestamp": "2026-01-31 12:34:56"
}
```

### Get User List

```bash
curl -u admin:password http://127.0.0.1:5000/api/users
```

Response:
```json
{
  "users": ["user8a3f12", "alice", "bob"]
}
```

## Service Management

### Check Dashboard Status

```bash
sudo systemctl status tortopus-dashboard
```

### View Dashboard Logs

```bash
sudo journalctl -u tortopus-dashboard -f
```

### Restart Dashboard

```bash
sudo systemctl restart tortopus-dashboard
```

### Stop Dashboard

```bash
sudo systemctl stop tortopus-dashboard
```

### Disable Dashboard

```bash
sudo systemctl disable tortopus-dashboard
```

## Configuration

Dashboard configuration file: `/opt/tortopus-dashboard/app.py`

### Change Admin Password

```bash
# Edit app.py
sudo nano /opt/tortopus-dashboard/app.py

# Find and change:
DASHBOARD_PASSWORD = 'your-new-password'

# Restart service
sudo systemctl restart tortopus-dashboard
```

### Change Admin Username

```bash
# Edit app.py
sudo nano /opt/tortopus-dashboard/app.py

# Find and change:
DASHBOARD_USER = 'your-new-username'

# Restart service
sudo systemctl restart tortopus-dashboard
```

### Change Port

```bash
# Edit app.py
sudo nano /opt/tortopus-dashboard/app.py

# Find and change (bottom of file):
app.run(host='127.0.0.1', port=5000, debug=False)

# Restart service
sudo systemctl restart tortopus-dashboard
```

## Security Notes

**IMPORTANT SECURITY PRACTICES:**

1. **Change default password** immediately after installation
2. **Use SSH tunnel** for remote access (recommended)
3. **Never expose** port 5000 directly to the internet
4. **Use nginx with SSL** if you need web-accessible dashboard
5. **Enable IP whitelisting** in nginx if using reverse proxy
6. **Monitor access logs** for suspicious activity

### IP Whitelisting with nginx

```nginx
# In nginx config
geo $allowed_ip {
    default 0;
    203.0.113.0/24 1;  # Your allowed IP range
}

server {
    ...
    location / {
        if ($allowed_ip = 0) {
            return 403;
        }
        proxy_pass http://127.0.0.1:5000;
    }
}
```

### Firewall Protection

```bash
# If using nginx on port 8443
# Only allow from specific IPs
sudo ufw delete allow 8443/tcp
sudo ufw allow from 203.0.113.0/24 to any port 8443 proto tcp
```

## Troubleshooting

### Dashboard Won't Start

```bash
# Check logs
sudo journalctl -u tortopus-dashboard -n 50

# Common issues:
# 1. Flask not installed
sudo pip3 install flask

# 2. Port already in use
sudo lsof -i :5000
```

### Can't Access Dashboard

```bash
# Verify service is running
sudo systemctl status tortopus-dashboard

# Check if listening on port
sudo ss -tlnp | grep 5000

# Test locally
curl -u admin:password http://127.0.0.1:5000/api/status
```

### Authentication Failed

```bash
# Verify credentials in app.py
sudo grep "DASHBOARD_" /opt/tortopus-dashboard/app.py

# Try resetting password
sudo nano /opt/tortopus-dashboard/app.py
# Change DASHBOARD_PASSWORD
sudo systemctl restart tortopus-dashboard
```

### Changes Not Reflecting

Dashboard directly modifies `/etc/squid/passwords` and reloads Squid.

```bash
# Verify Squid reloaded
sudo systemctl status squid

# Manually reload if needed
sudo systemctl reload squid

# Check password file
sudo cat /etc/squid/passwords
```

## Uninstall

```bash
# Stop and disable service
sudo systemctl stop tortopus-dashboard
sudo systemctl disable tortopus-dashboard

# Remove service file
sudo rm /etc/systemd/system/tortopus-dashboard.service
sudo systemctl daemon-reload

# Remove dashboard files
sudo rm -rf /opt/tortopus-dashboard
```

## Development

Dashboard is built with:
- Python 3
- Flask web framework
- No database (direct file manipulation)
- Bootstrap CSS (inline)

Source code: `/opt/tortopus-dashboard/app.py`

### Running in Development Mode

```bash
cd /opt/tortopus-dashboard
sudo python3 app.py
```

This runs Flask in debug mode on `http://127.0.0.1:5000`
