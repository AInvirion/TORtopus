#!/usr/bin/env python3
"""
TORtopus Proxy Test Script
Tests both Squid HTTP proxy and Tor SOCKS5 proxy connectivity
"""

import sys
import argparse
import urllib.request
import urllib.error
import socket
from urllib.parse import quote

try:
    import socks  # PySocks for SOCKS5 support
except ImportError:
    print("⚠️  Warning: PySocks not installed. SOCKS5 tests will be skipped.")
    print("   Install with: pip install PySocks")
    socks = None


class Colors:
    """ANSI color codes for terminal output"""
    BLUE = '\033[0;34m'
    GREEN = '\033[0;32m'
    RED = '\033[0;31m'
    YELLOW = '\033[1;33m'
    CYAN = '\033[0;36m'
    NC = '\033[0m'  # No Color


def print_header(text):
    """Print a colored header"""
    print(f"\n{Colors.CYAN}{'='*60}{Colors.NC}")
    print(f"{Colors.CYAN}{text}{Colors.NC}")
    print(f"{Colors.CYAN}{'='*60}{Colors.NC}\n")


def print_success(text):
    """Print success message"""
    print(f"{Colors.GREEN}✓{Colors.NC} {text}")


def print_error(text):
    """Print error message"""
    print(f"{Colors.RED}✗{Colors.NC} {text}")


def print_info(text):
    """Print info message"""
    print(f"{Colors.BLUE}ℹ{Colors.NC} {text}")


def get_ip_direct():
    """Get IP address without proxy"""
    try:
        with urllib.request.urlopen('https://ifconfig.me', timeout=10) as response:
            return response.read().decode('utf-8').strip()
    except Exception as e:
        return f"Error: {e}"


def test_http_proxy(host, port, username, password):
    """Test HTTP proxy (Squid)"""
    print_header("Testing HTTP Proxy (Squid)")

    # URL encode password to handle special characters
    encoded_password = quote(password, safe='')
    proxy_url = f'http://{username}:{encoded_password}@{host}:{port}'

    print_info(f"Proxy: {host}:{port}")
    print_info(f"User: {username}")
    print_info("Testing connection...")

    # Configure proxy
    proxy_handler = urllib.request.ProxyHandler({
        'http': proxy_url,
        'https': proxy_url
    })
    opener = urllib.request.build_opener(proxy_handler)

    try:
        # Test connection
        request = urllib.request.Request('https://ifconfig.me')
        with opener.open(request, timeout=15) as response:
            ip = response.read().decode('utf-8').strip()
            print_success(f"Connected via HTTP proxy")
            print_success(f"Your IP: {ip}")
            return True, ip
    except urllib.error.HTTPError as e:
        if e.code == 407:
            print_error("Authentication failed (407 Proxy Authentication Required)")
            print_error("Check username and password")
        else:
            print_error(f"HTTP Error: {e.code} - {e.reason}")
        return False, None
    except urllib.error.URLError as e:
        print_error(f"Connection failed: {e.reason}")
        return False, None
    except Exception as e:
        print_error(f"Unexpected error: {e}")
        return False, None


def test_socks5_proxy(host, port, username, password):
    """Test SOCKS5 proxy (Tor)"""
    print_header("Testing SOCKS5 Proxy (Tor)")

    if socks is None:
        print_error("PySocks not installed. Skipping SOCKS5 test.")
        print_info("Install with: pip install PySocks")
        return False, None

    print_info(f"Proxy: {host}:{port}")
    print_info(f"User: {username}")
    print_info("Testing Tor connection...")

    try:
        # Create a socket with SOCKS5 proxy
        s = socks.socksocket()
        s.set_proxy(
            proxy_type=socks.SOCKS5,
            addr=host,
            port=port,
            username=username,
            password=password
        )

        # Connect to ifconfig.me via Tor
        s.settimeout(30)
        s.connect(("ifconfig.me", 80))

        # Send HTTP request
        request = b"GET / HTTP/1.1\r\nHost: ifconfig.me\r\nConnection: close\r\n\r\n"
        s.sendall(request)

        # Read response
        response = b""
        while True:
            chunk = s.recv(4096)
            if not chunk:
                break
            response += chunk

        s.close()

        # Extract IP from response
        response_text = response.decode('utf-8', errors='ignore')
        ip = response_text.split('\r\n\r\n')[-1].strip()

        print_success("Connected via SOCKS5 proxy")
        print_success(f"Your IP: {ip}")

        # Test if we're using Tor
        print_info("Checking Tor status...")
        test_tor_connection(host, port, username, password)

        return True, ip
    except Exception as e:
        print_error(f"SOCKS5 connection failed: {e}")
        return False, None


def test_tor_connection(host, port, username, password):
    """Verify connection is through Tor network"""
    try:
        s = socks.socksocket()
        s.set_proxy(
            proxy_type=socks.SOCKS5,
            addr=host,
            port=port,
            username=username,
            password=password
        )

        s.settimeout(30)
        s.connect(("check.torproject.org", 443))

        # Simple HTTPS check (won't validate certificate)
        import ssl
        context = ssl.create_default_context()
        context.check_hostname = False
        context.verify_mode = ssl.CERT_NONE

        with context.wrap_socket(s, server_hostname="check.torproject.org") as secure_sock:
            request = b"GET / HTTP/1.1\r\nHost: check.torproject.org\r\nConnection: close\r\n\r\n"
            secure_sock.sendall(request)

            response = b""
            while True:
                chunk = secure_sock.recv(4096)
                if not chunk:
                    break
                response += chunk

            response_text = response.decode('utf-8', errors='ignore')

            if "Congratulations" in response_text or "You are using Tor" in response_text.lower():
                print_success("Confirmed: You are using Tor! 🧅")
            else:
                print_error("Warning: Tor check failed")
    except Exception as e:
        print_info(f"Tor verification skipped: {e}")


def main():
    parser = argparse.ArgumentParser(
        description='Test TORtopus proxy connectivity',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Test HTTP proxy only
  %(prog)s -s proxy.example.com -u myuser -p mypass

  # Test both HTTP and SOCKS5
  %(prog)s -s proxy.example.com -u myuser -p mypass --test-all

  # Custom ports
  %(prog)s -s proxy.example.com -u myuser -p mypass --http-port 8080 --socks-port 1080
        """
    )

    parser.add_argument('-s', '--server', required=True, help='Proxy server hostname or IP')
    parser.add_argument('-u', '--username', required=True, help='Proxy username')
    parser.add_argument('-p', '--password', required=True, help='Proxy password')
    parser.add_argument('--http-port', type=int, default=3128, help='HTTP proxy port (default: 3128)')
    parser.add_argument('--socks-port', type=int, default=9050, help='SOCKS5 proxy port (default: 9050)')
    parser.add_argument('--test-all', action='store_true', help='Test both HTTP and SOCKS5')
    parser.add_argument('--socks-only', action='store_true', help='Test only SOCKS5')
    parser.add_argument('--no-direct', action='store_true', help='Skip direct connection test')

    args = parser.parse_args()

    # Print banner
    print(f"\n{Colors.BLUE}{'='*60}")
    print("  TORtopus Proxy Test Script")
    print(f"{'='*60}{Colors.NC}\n")

    results = {}

    # Test direct connection
    if not args.no_direct:
        print_header("Direct Connection (No Proxy)")
        print_info("Getting your real IP...")
        direct_ip = get_ip_direct()
        if "Error" not in direct_ip:
            print_success(f"Your real IP: {direct_ip}")
            results['direct'] = direct_ip
        else:
            print_error(f"Could not get direct IP: {direct_ip}")

    # Test HTTP proxy
    if not args.socks_only:
        success, ip = test_http_proxy(
            args.server,
            args.http_port,
            args.username,
            args.password
        )
        if success:
            results['http'] = ip

    # Test SOCKS5 proxy
    if args.test_all or args.socks_only:
        success, ip = test_socks5_proxy(
            args.server,
            args.socks_port,
            args.username,
            args.password
        )
        if success:
            results['socks5'] = ip

    # Print summary
    print_header("Summary")

    if 'direct' in results:
        print(f"  Direct IP:      {results['direct']}")
    if 'http' in results:
        print(f"  HTTP Proxy IP:  {results['http']}")
    if 'socks5' in results:
        print(f"  SOCKS5/Tor IP:  {results['socks5']}")

    # Check if IPs are different (privacy verification)
    if len(results) > 1:
        ips = list(results.values())
        if len(set(ips)) > 1:
            print(f"\n{Colors.GREEN}✓ Privacy verified: Your IP is hidden!{Colors.NC}")
        else:
            print(f"\n{Colors.YELLOW}⚠ All IPs are the same{Colors.NC}")

    print()  # Empty line at end


if __name__ == '__main__':
    try:
        main()
    except KeyboardInterrupt:
        print(f"\n\n{Colors.YELLOW}Test interrupted by user{Colors.NC}\n")
        sys.exit(1)
    except Exception as e:
        print(f"\n{Colors.RED}Unexpected error: {e}{Colors.NC}\n")
        sys.exit(1)
