#!/bin/bash
# ============================================================
# curl-cffi 0.16.3 Installer for 32-bit Android ARM
# Built with libcurl-impersonate + BoringSSL
# Supports: Chrome, Firefox, Safari, Edge impersonation
# ============================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ---- Detect environment ----
detect_env() {
    if [ -n "$TERMUX_VERSION" ] || [ -n "$ANDROID_ROOT" ]; then
        if command -v python3 &>/dev/null; then
            PYTHON_VERSION=$(python3 -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
            SITE_PACKAGES=$(python3 -c "import site; print(site.getsitepackages()[0])" 2>/dev/null || \
                           echo "/data/data/com.termux/files/usr/lib/python${PYTHON_VERSION}/site-packages")
        else
            error "Python3 not found. Install with: pkg install python"
            exit 1
        fi
        ENV="termux"
        LIB_DIR="/data/data/com.termux/files/usr/lib"
    elif [ -d "/usr/lib/python3" ]; then
        SITE_PACKAGES=$(python3 -c "import site; print(site.getsitepackages()[0])")
        PYTHON_VERSION=$(python3 -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
        LIB_DIR="/usr/lib"
        ENV="linux"
    else
        error "Unsupported environment. This package is for Android/Termux."
        exit 1
    fi

    info "Environment: $ENV"
    info "Python: $PYTHON_VERSION"
    info "Site-packages: $SITE_PACKAGES"
}

# ---- Check Python version ----
check_python() {
    local major minor
    major=$(python3 -c "import sys; print(sys.version_info.major)")
    minor=$(python3 -c "import sys; print(sys.version_info.minor)")

    if [ "$major" -lt 3 ] || { [ "$major" -eq 3 ] && [ "$minor" -lt 10 ]; }; then
        error "Python 3.10+ required. Found: $major.$minor"
        exit 1
    fi

    if [ "$major" -ne 3 ] || [ "$minor" -ne 14 ]; then
        warn "Built for Python 3.14, found $major.$minor. May have compatibility issues."
    fi
}

# ---- Check architecture ----
check_arch() {
    local arch
    arch=$(uname -m)
    case "$arch" in
        armv7l|armv8l|arm)
            info "Architecture: $arch (32-bit ARM) ✓"
            ;;
        *)
            error "Unsupported architecture: $arch. This package is for 32-bit ARM only."
            exit 1
            ;;
    esac
}

# ---- Install dependencies ----
install_deps() {
    info "Installing dependencies..."

    # cffi
    if [ ! -d "$SITE_PACKAGES/cffi" ]; then
        cp -r "$SCRIPT_DIR/deps/cffi" "$SITE_PACKAGES/"
        info "Installed cffi"
    else
        warn "cffi already exists, skipping"
    fi

    # _cffi_backend
    for f in "$SCRIPT_DIR/deps/"_cffi_backend*.so; do
        [ -f "$f" ] && cp "$f" "$SITE_PACKAGES/"
    done
    info "Installed _cffi_backend"

    # certifi
    if [ ! -d "$SITE_PACKAGES/certifi" ]; then
        cp -r "$SCRIPT_DIR/deps/certifi" "$SITE_PACKAGES/"
        info "Installed certifi"
    else
        warn "certifi already exists, skipping"
    fi

    # pycparser
    if [ ! -d "$SITE_PACKAGES/pycparser" ]; then
        cp -r "$SCRIPT_DIR/deps/pycparser" "$SITE_PACKAGES/"
        info "Installed pycparser"
    else
        warn "pycparser already exists, skipping"
    fi

    # libc++_shared.so
    if [ ! -f "$LIB_DIR/libc++_shared.so" ]; then
        cp "$SCRIPT_DIR/deps/libc++_shared.so" "$LIB_DIR/"
        info "Installed libc++_shared.so"
    else
        warn "libc++_shared.so already exists, skipping"
    fi
}

# ---- Install curl_cffi ----
install_curl_cffi() {
    info "Installing curl_cffi..."

    # Backup existing installation
    if [ -d "$SITE_PACKAGES/curl_cffi" ]; then
        backup="$SITE_PACKAGES/curl_cffi.bak.$(date +%s)"
        mv "$SITE_PACKAGES/curl_cffi" "$backup"
        info "Backed up existing curl_cffi to $backup"
    fi

    # Copy package
    cp -r "$SCRIPT_DIR/curl_cffi" "$SITE_PACKAGES/"
    chmod 755 "$SITE_PACKAGES/curl_cffi/_wrapper.abi3.so"

    info "Installed curl_cffi 0.16.3"
}

# ---- Verify installation ----
verify() {
    info "Verifying installation..."

    if python3 -c "
from curl_cffi import requests
import json

# Test basic request
r = requests.get('https://httpbin.org/get')
assert r.status_code == 200, f'GET failed: {r.status_code}'

# Test impersonation
r = requests.get('https://httpbin.org/headers', impersonate='chrome')
data = r.json()
ua = data['headers'].get('User-Agent', '')
assert 'Chrome' in ua, f'Impersonation failed: {ua}'

import curl_cffi
print(f'curl-cffi {curl_cffi.__version__}')
print(f'libcurl {curl_cffi.__curl_version__}')
print('All tests passed!')
" 2>&1; then
        info "✅ Installation verified successfully!"
    else
        error "Verification failed. Check the output above."
        exit 1
    fi
}

# ---- Main ----
main() {
    echo ""
    echo "╔══════════════════════════════════════════════════╗"
    echo "║  curl-cffi 0.16.3 - 32-bit Android ARM Installer ║"
    echo "║  With impersonation support (Chrome/Firefox/etc) ║"
    echo "╚══════════════════════════════════════════════════╝"
    echo ""

    detect_env
    check_python
    check_arch
    install_deps
    install_curl_cffi
    verify

    echo ""
    info "Installation complete!"
    info "Usage: from curl_cffi import requests"
    info "       r = requests.get('https://example.com', impersonate='chrome')"
    echo ""
}

main "$@"
