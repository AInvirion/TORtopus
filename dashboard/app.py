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
SQUID_CONFIG_FILE = '/etc/squid/squid.conf'
SQUID_ACCESS_LOG = '/var/log/squid/access.log'
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

    # Validate password (alphanumeric only - no special characters)
    if not re.match(r'^[a-zA-Z0-9]+$', password):
        return False, "Password must contain only letters and numbers (no special characters)"

    # Validate password length
    if len(password) < 8:
        return False, "Password must be at least 8 characters long"

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

    # Validate password (alphanumeric only)
    if not re.match(r'^[a-zA-Z0-9]+$', new_password):
        return False, "Password must contain only letters and numbers (no special characters)"

    # Validate password length
    if len(new_password) < 8:
        return False, "Password must be at least 8 characters long"

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

def get_proxy_mode():
    """Get current proxy mode (direct or tor)"""
    try:
        if os.path.exists(SQUID_CONFIG_FILE):
            with open(SQUID_CONFIG_FILE, 'r') as f:
                content = f.read()
                # Check for active (uncommented) cache_peer line with port 8118 (Privoxy)
                if re.search(r'^cache_peer\s+127\.0\.0\.1\s+parent\s+8118', content, re.MULTILINE):
                    return 'tor'
                # Also check for old port 9050 (direct to Tor, which doesn't work but might exist)
                if re.search(r'^cache_peer\s+127\.0\.0\.1\s+parent\s+9050', content, re.MULTILINE):
                    return 'tor'
        return 'direct'
    except Exception as e:
        print(f"Error reading proxy mode: {e}")
        return 'unknown'

def set_proxy_mode(mode):
    """Set proxy mode (direct or tor)"""
    if mode not in ['direct', 'tor']:
        return False, "Invalid mode. Use 'direct' or 'tor'"

    success, stdout, stderr = run_command(f'tortopus-config --mode {mode}')

    if success:
        return True, f"Proxy mode changed to {mode}"
    else:
        return False, f"Failed to change mode: {stderr}"

def parse_squid_log_line(line):
    """Parse a single Squid access log line"""
    try:
        parts = line.split()
        if len(parts) < 10:
            return None

        # Parse timestamp (Unix epoch with milliseconds)
        timestamp = float(parts[0])
        dt = datetime.fromtimestamp(timestamp)

        # Parse result code (e.g., TCP_MISS/200)
        result_parts = parts[3].split('/')
        squid_code = result_parts[0] if len(result_parts) > 0 else 'UNKNOWN'
        http_code = result_parts[1] if len(result_parts) > 1 else '0'

        # Determine if successful (2xx or 3xx status codes)
        try:
            http_code_int = int(http_code)
            is_success = 200 <= http_code_int < 400
        except:
            is_success = False

        return {
            'timestamp': dt.strftime('%Y-%m-%d %H:%M:%S'),
            'elapsed_ms': parts[1],
            'client_ip': parts[2],
            'squid_code': squid_code,
            'http_code': http_code,
            'is_success': is_success,
            'size': parts[4],
            'method': parts[5],
            'url': parts[6][:80] + '...' if len(parts[6]) > 80 else parts[6],
            'full_url': parts[6],
            'user': parts[7] if parts[7] != '-' else 'anonymous',
            'peer': parts[8] if len(parts) > 8 else '-',
        }
    except Exception as e:
        return None

def get_recent_connections(limit=100, filter_user=None, filter_status=None):
    """Get recent connections from Squid access log"""
    connections = []

    try:
        if not os.path.exists(SQUID_ACCESS_LOG):
            return connections

        # Read last N lines efficiently using tail
        success, stdout, stderr = run_command(f'tail -n {limit * 2} "{SQUID_ACCESS_LOG}"')

        if not success or not stdout:
            return connections

        lines = stdout.strip().split('\n')

        for line in reversed(lines):  # Most recent first
            if len(connections) >= limit:
                break

            parsed = parse_squid_log_line(line)
            if parsed:
                # Apply filters
                if filter_user and parsed['user'] != filter_user:
                    continue
                if filter_status == 'success' and not parsed['is_success']:
                    continue
                if filter_status == 'failed' and parsed['is_success']:
                    continue

                connections.append(parsed)

        return connections
    except Exception as e:
        print(f"Error reading access log: {e}")
        return connections

def get_connection_stats():
    """Get connection statistics"""
    stats = {
        'total_today': 0,
        'successful': 0,
        'failed': 0,
        'unique_ips': set(),
        'by_user': {},
        'by_status': {}
    }

    try:
        if not os.path.exists(SQUID_ACCESS_LOG):
            return stats

        # Get today's date
        today = datetime.now().strftime('%Y-%m-%d')

        # Read recent log entries
        success, stdout, stderr = run_command(f'tail -n 1000 "{SQUID_ACCESS_LOG}"')

        if not success or not stdout:
            return stats

        for line in stdout.strip().split('\n'):
            parsed = parse_squid_log_line(line)
            if not parsed:
                continue

            # Only count today's entries
            if parsed['timestamp'].startswith(today):
                stats['total_today'] += 1
                stats['unique_ips'].add(parsed['client_ip'])

                if parsed['is_success']:
                    stats['successful'] += 1
                else:
                    stats['failed'] += 1

                # Count by user
                user = parsed['user']
                stats['by_user'][user] = stats['by_user'].get(user, 0) + 1

                # Count by HTTP status
                http_code = parsed['http_code']
                stats['by_status'][http_code] = stats['by_status'].get(http_code, 0) + 1

        stats['unique_ips'] = len(stats['unique_ips'])

    except Exception as e:
        print(f"Error getting stats: {e}")

    return stats

def get_system_status():
    """Get system and service status"""
    status = {
        'squid': 'unknown',
        'tor': 'unknown',
        'privoxy': 'unknown',
        'fail2ban': 'unknown',
        'ufw': 'unknown',
        'proxy_mode': get_proxy_mode(),
        'user_count': len(get_proxy_users()),
        'timestamp': datetime.now().strftime('%Y-%m-%d %H:%M:%S')
    }

    services = ['squid', 'tor@default', 'privoxy', 'fail2ban', 'ufw']
    service_keys = ['squid', 'tor', 'privoxy', 'fail2ban', 'ufw']

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
    allowed_services = ['squid', 'tor@default', 'privoxy', 'fail2ban']

    if service not in allowed_services:
        flash('Invalid service', 'error')
        return redirect(url_for('index'))

    success, stdout, stderr = run_command(f'systemctl restart {service}')

    if success:
        flash(f'Service {service} restarted successfully', 'success')
    else:
        flash(f'Failed to restart {service}: {stderr}', 'error')

    return redirect(url_for('index'))

@app.route('/set_proxy_mode/<mode>', methods=['POST'])
@requires_auth
def change_proxy_mode(mode):
    """Change proxy mode (direct or tor)"""
    success, message = set_proxy_mode(mode)
    flash(message, 'success' if success else 'error')
    return redirect(url_for('index'))

@app.route('/connections')
@requires_auth
def connections():
    """View recent proxy connections"""
    # Get filter parameters
    filter_user = request.args.get('user', None)
    filter_status = request.args.get('status', None)
    limit = int(request.args.get('limit', 100))

    # Cap limit at 500
    limit = min(limit, 500)

    recent_connections = get_recent_connections(limit, filter_user, filter_status)
    stats = get_connection_stats()
    users = get_proxy_users()

    return render_template('connections.html',
                           connections=recent_connections,
                           stats=stats,
                           users=users,
                           filter_user=filter_user,
                           filter_status=filter_status,
                           limit=limit)

@app.route('/api/connections')
@requires_auth
def api_connections():
    """API endpoint for connections"""
    filter_user = request.args.get('user', None)
    filter_status = request.args.get('status', None)
    limit = int(request.args.get('limit', 100))
    limit = min(limit, 500)

    connections = get_recent_connections(limit, filter_user, filter_status)
    stats = get_connection_stats()

    return jsonify({
        'connections': connections,
        'stats': stats
    })

if __name__ == '__main__':
    # Check if running as root
    if os.geteuid() != 0:
        print("Warning: This application should be run as root to manage Squid users")

    # Run on localhost only by default (use nginx/apache as reverse proxy)
    app.run(host='127.0.0.1', port=5000, debug=False)
