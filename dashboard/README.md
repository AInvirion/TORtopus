# TORtopus Web Dashboard

A simple, secure web interface for managing TORtopus proxy users.

## Features

- ✅ Add/Remove proxy users
- ✅ Change user passwords
- ✅ View system status (Squid, Tor, fail2ban, UFW)
- ✅ No database required (file-based)
- ✅ HTTP Basic Authentication
- ✅ Clean, modern UI
- ✅ Runs as systemd service

## Installation

### Automatic (via TORtopus installer)

The dashboard is installed automatically if you choose to install it during the main TORtopus installation.

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
# Change: DASHBOARD_PASSWORD = 'changeme123'

# Install systemd service
sudo cp tortopus-dashboard.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable tortopus-dashboard
sudo systemctl start tortopus-dashboard
```

## Access

### Local Access (from server)

```bash
curl http://127.0.0.1:5000
```

### Remote Access (via SSH tunnel - RECOMMENDED)

```bash
# From your local machine
ssh -L 5000:127.0.0.1:5000 root@YOUR_SERVER_IP -p SSH_PORT

# Then open in browser
http://localhost:5000
```

**Default credentials:**
- Username: `admin`
- Password: `changeme123` (CHANGE THIS!)

### Remote Access (via nginx reverse proxy with SSL)

**Recommended for production use:**

```bash
# Install nginx
sudo apt-get install -y nginx certbot python3-certbot-nginx

# Configure nginx
sudo nano /etc/nginx/sites-available/tortopus-dashboard

# Add:
server {
    listen 8443 ssl;
    server_name your-domain.com;

    ssl_certificate /etc/ssl/certs/tortopus.crt;
    ssl_certificate_key /etc/ssl/private/tortopus.key;

    location / {
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}

# Enable site
sudo ln -s /etc/nginx/sites-available/tortopus-dashboard /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl restart nginx

# Allow port in firewall
sudo ufw allow 8443/tcp
```

Then access at: `https://your-server:8443`

## Security Notes

⚠️ **IMPORTANT:**

1. **Change the default password** in `app.py`:
   ```python
   DASHBOARD_PASSWORD = 'your-strong-password-here'
   ```

2. **Use SSH tunnel** for remote access (safest):
   ```bash
   ssh -L 5000:127.0.0.1:5000 root@server
   ```

3. **Or use nginx with SSL** for HTTPS access

4. **Never expose** port 5000 directly to the internet

5. **Consider** adding IP whitelisting in nginx/ufw

## API Endpoints

The dashboard also provides simple API endpoints:

```bash
# Get system status
curl -u admin:password http://127.0.0.1:5000/api/status

# Get user list
curl -u admin:password http://127.0.0.1:5000/api/users
```

## Troubleshooting

### Check service status
```bash
sudo systemctl status tortopus-dashboard
```

### View logs
```bash
sudo journalctl -u tortopus-dashboard -f
```

### Restart dashboard
```bash
sudo systemctl restart tortopus-dashboard
```

### Test locally
```bash
curl -u admin:changeme123 http://127.0.0.1:5000/api/status
```

## Uninstall

```bash
sudo systemctl stop tortopus-dashboard
sudo systemctl disable tortopus-dashboard
sudo rm /etc/systemd/system/tortopus-dashboard.service
sudo rm -rf /opt/tortopus-dashboard
sudo systemctl daemon-reload
```
