#!/usr/bin/env python3
"""
TORtopus Web Dashboard
Simple web interface for managing Squid proxy users
"""

from flask import Flask, render_template, request, redirect, url_for, flash, jsonify
from functools import wraps
import subprocess
import os
import re
from datetime import datetime

app = Flask(__name__)
app.secret_key = os.urandom(24)  # Change this to a fixed secret in production

# Configuration
SQUID_PASSWORDS_FILE = '/etc/squid/passwords'
DASHBOARD_USER = 'admin'
DASHBOARD_PASSWORD = 'changeme123'  # CHANGE THIS!

def check_auth(username, password):
    """Check if username/password combination is valid"""
    return username == DASHBOARD_USER and password == DASHBOARD_PASSWORD

def authenticate():
    """Send 401 response for authentication"""
    return ('Authentication required', 401,
            {'WWW-Authenticate': 'Basic realm="TORtopus Dashboard"'})

def requires_auth(f):
    """Decorator for routes that require authentication"""
    @wraps(f)
    def decorated(*args, **kwargs):
        auth = request.authorization
        if not auth or not check_auth(auth.username, auth.password):
            return authenticate()
        return f(*args, **kwargs)
    return decorated

def run_command(cmd):
    """Run a shell command and return output"""
    try:
        result = subprocess.run(
            cmd,
            shell=True,
            capture_output=True,
            text=True,
            timeout=10
        )
        return result.returncode == 0, result.stdout, result.stderr
    except subprocess.TimeoutExpired:
        return False, "", "Command timed out"
    except Exception as e:
        return False, "", str(e)

def get_proxy_users():
    """Get list of proxy users from password file"""
    users = []
    try:
        if os.path.exists(SQUID_PASSWORDS_FILE):
            with open(SQUID_PASSWORDS_FILE, 'r') as f:
                for line in f:
                    line = line.strip()
                    if line and ':' in line:
                        username = line.split(':')[0]
                        users.append(username)
        return sorted(users)
    except Exception as e:
        print(f"Error reading users: {e}")
        return []

def add_proxy_user(username, password):
    """Add a new proxy user"""
    # Validate username (alphanumeric and underscore only)
    if not re.match(r'^[a-zA-Z0-9_]+$', username):
        return False, "Username must contain only letters, numbers, and underscores"

    # Check if user already exists
    users = get_proxy_users()
    if username in users:
        return False, f"User '{username}' already exists"

    # Add user using htpasswd
    success, stdout, stderr = run_command(
        f'htpasswd -b "{SQUID_PASSWORDS_FILE}" "{username}" "{password}"'
    )

    if success:
        # Reload Squid
        run_command('systemctl reload squid')
        return True, f"User '{username}' added successfully"
    else:
        return False, f"Failed to add user: {stderr}"

def remove_proxy_user(username):
    """Remove a proxy user"""
    users = get_proxy_users()
    if username not in users:
        return False, f"User '{username}' not found"

    # Remove user using htpasswd
    success, stdout, stderr = run_command(
        f'htpasswd -D "{SQUID_PASSWORDS_FILE}" "{username}"'
    )

    if success:
        # Reload Squid
        run_command('systemctl reload squid')
        return True, f"User '{username}' removed successfully"
    else:
        return False, f"Failed to remove user: {stderr}"

def change_user_password(username, new_password):
    """Change a user's password"""
    users = get_proxy_users()
    if username not in users:
        return False, f"User '{username}' not found"

    # Update password using htpasswd
    success, stdout, stderr = run_command(
        f'htpasswd -b "{SQUID_PASSWORDS_FILE}" "{username}" "{new_password}"'
    )

    if success:
        # Reload Squid
        run_command('systemctl reload squid')
        return True, f"Password for '{username}' changed successfully"
    else:
        return False, f"Failed to change password: {stderr}"

def get_system_status():
    """Get system and service status"""
    status = {
        'squid': 'unknown',
        'tor': 'unknown',
        'fail2ban': 'unknown',
        'ufw': 'unknown',
        'user_count': len(get_proxy_users()),
        'timestamp': datetime.now().strftime('%Y-%m-%d %H:%M:%S')
    }

    services = ['squid', 'tor@default', 'fail2ban', 'ufw']
    service_keys = ['squid', 'tor', 'fail2ban', 'ufw']

    for service, key in zip(services, service_keys):
        success, stdout, stderr = run_command(f'systemctl is-active {service}')
        if success and 'active' in stdout:
            status[key] = 'active'
        else:
            status[key] = 'inactive'

    return status

@app.route('/')
@requires_auth
def index():
    """Main dashboard page"""
    users = get_proxy_users()
    status = get_system_status()
    return render_template('index.html', users=users, status=status)

@app.route('/add_user', methods=['POST'])
@requires_auth
def add_user():
    """Add a new user"""
    username = request.form.get('username', '').strip()
    password = request.form.get('password', '')

    if not username or not password:
        flash('Username and password are required', 'error')
        return redirect(url_for('index'))

    success, message = add_proxy_user(username, password)
    flash(message, 'success' if success else 'error')
    return redirect(url_for('index'))

@app.route('/remove_user/<username>', methods=['POST'])
@requires_auth
def remove_user(username):
    """Remove a user"""
    success, message = remove_proxy_user(username)
    flash(message, 'success' if success else 'error')
    return redirect(url_for('index'))

@app.route('/change_password', methods=['POST'])
@requires_auth
def change_password():
    """Change user password"""
    username = request.form.get('username', '').strip()
    new_password = request.form.get('new_password', '')

    if not username or not new_password:
        flash('Username and new password are required', 'error')
        return redirect(url_for('index'))

    success, message = change_user_password(username, new_password)
    flash(message, 'success' if success else 'error')
    return redirect(url_for('index'))

@app.route('/api/status')
@requires_auth
def api_status():
    """API endpoint for system status"""
    return jsonify(get_system_status())

@app.route('/api/users')
@requires_auth
def api_users():
    """API endpoint for user list"""
    return jsonify({'users': get_proxy_users()})

@app.route('/restart_service/<service>', methods=['POST'])
@requires_auth
def restart_service(service):
    """Restart a service"""
    allowed_services = ['squid', 'tor@default', 'fail2ban']

    if service not in allowed_services:
        flash('Invalid service', 'error')
        return redirect(url_for('index'))

    success, stdout, stderr = run_command(f'systemctl restart {service}')

    if success:
        flash(f'Service {service} restarted successfully', 'success')
    else:
        flash(f'Failed to restart {service}: {stderr}', 'error')

    return redirect(url_for('index'))

if __name__ == '__main__':
    # Check if running as root
    if os.geteuid() != 0:
        print("Warning: This application should be run as root to manage Squid users")

    # Run on localhost only by default (use nginx/apache as reverse proxy)
    app.run(host='127.0.0.1', port=5000, debug=False)
