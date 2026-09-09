#!/bin/bash
# curl-cffi Uninstaller for 32-bit Android ARM

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Detect site-packages
if [ -n "$TERMUX_VERSION" ] || [ -n "$ANDROID_ROOT" ]; then
    SITE_PACKAGES=$(python3 -c "import site; print(site.getsitepackages()[0])" 2>/dev/null || \
                   echo "/data/data/com.termux/files/usr/lib/python3.14/site-packages")
else
    SITE_PACKAGES=$(python3 -c "import site; print(site.getsitepackages()[0])")
fi

info "Removing curl_cffi..."
rm -rf "$SITE_PACKAGES/curl_cffi"

info "Removing backup if exists..."
rm -rf "$SITE_PACKAGES/curl_cffi.bak."*

# Restore backed up version if exists
backup=$(ls -td "$SITE_PACKAGES"/curl_cffi.bak.* 2>/dev/null | head -1)
if [ -n "$backup" ]; then
    info "Restoring from backup: $backup"
    mv "$backup" "$SITE_PACKAGES/curl_cffi"
fi

info "curl-cffi has been removed."
info "Note: cffi, certifi, pycparser, and libc++_shared.so were NOT removed."
info "They may be used by other packages."
echo ""
info "To remove them manually:"
info "  rm -rf $SITE_PACKAGES/cffi"
info "  rm -rf $SITE_PACKAGES/certifi"
info "  rm -rf $SITE_PACKAGES/pycparser"
