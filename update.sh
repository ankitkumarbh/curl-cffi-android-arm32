#!/bin/bash
# ============================================================
# curl-cffi Updater for 32-bit Android ARM
# Smart build - skips completed steps, resumes from failures
# ============================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
GRAY='\033[0;90m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }
step()  { echo -e "${CYAN}[STEP]${NC} $1"; }
skip()  { echo -e "${GRAY}[SKIP]${NC} $1 (already done)"; }
done_msg() { echo -e "${GREEN}[DONE]${NC} $1"; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
STATE_DIR="$HOME/.curl-cffi-build-state"

# ---- State management ----
state_file() { echo "$STATE_DIR/$1.done"; }

state_done() {
    touch "$(state_file "$1")"
}

state_check() {
    [ -f "$(state_file "$1")" ]
}

state_clear() {
    rm -f "$STATE_DIR"/*.done
}

state_list() {
    echo "=== Build State ==="
    local found=0
    for f in "$STATE_DIR"/*.done; do
        if [ -f "$f" ]; then
            echo "  ✓ $(basename "$f" .done)"
            found=1
        fi
    done
    [ $found -eq 0 ] && echo "  (none)"
}

# ---- Detect environment ----
detect_env() {
    if [ -n "$TERMUX_VERSION" ] || [ -n "$ANDROID_ROOT" ]; then
        SITE_PACKAGES=$(python3 -c "import site; print(site.getsitepackages()[0])" 2>/dev/null || \
                       echo "/data/data/com.termux/files/usr/lib/python3.14/site-packages")
        LIB_DIR="/data/data/com.termux/files/usr/lib"
        ENV="termux"
    else
        SITE_PACKAGES=$(python3 -c "import site; print(site.getsitepackages()[0])")
        LIB_DIR="/usr/lib"
        ENV="linux"
    fi
    mkdir -p "$STATE_DIR"
}

# ---- Check current version ----
check_current() {
    CURRENT=$(python3 -c "
import sys
# Remove local directory from path to avoid importing local copy
sys.path = [p for p in sys.path if p not in ('', '.')]
try:
    import curl_cffi
    print(curl_cffi.__version__)
except:
    print('not installed')
" 2>/dev/null)
    info "Current version: $CURRENT"
}

check_latest() {
    # Try pip first, then PyPI API
    LATEST=$(pip index versions curl-cffi 2>/dev/null | head -1 | grep -oP '[\d.]+' | head -1)
    if [ -z "$LATEST" ]; then
        LATEST=$(curl -s "https://pypi.org/pypi/curl-cffi/json" | python3 -c "import sys,json; print(json.load(sys.stdin)['info']['version'])" 2>/dev/null)
    fi
    if [ -z "$LATEST" ]; then
        LATEST="unknown"
    fi
    info "Latest version: $LATEST"
}

# ---- Step 1: Build dependencies ----
install_build_deps() {
    if state_check "build_deps"; then
        skip "Build dependencies"
        return 0
    fi

    step "Checking build dependencies..."

    if [ "$ENV" = "termux" ]; then
        pkg update -y 2>/dev/null || true
    fi

    local NEED_INSTALL=""

    command -v cmake &>/dev/null || NEED_INSTALL="$NEED_INSTALL cmake"
    command -v ninja &>/dev/null || NEED_INSTALL="$NEED_INSTALL ninja"
    command -v clang &>/dev/null || NEED_INSTALL="$NEED_INSTALL clang"
    command -v git &>/dev/null || NEED_INSTALL="$NEED_INSTALL git"

    if [ -n "$NEED_INSTALL" ] && [ "$ENV" = "termux" ]; then
        info "Installing:$NEED_INSTALL"
        pkg install -y $NEED_INSTALL
    fi

    # Verify
    for cmd in cmake ninja clang git; do
        if ! command -v $cmd &>/dev/null; then
            error "$cmd not found and cannot be installed"
            return 1
        fi
    done

    state_done "build_deps"
    done_msg "Build dependencies"
}

# ---- Step 2: Install Go ----
install_go() {
    if state_check "go"; then
        skip "Go"
        return 0
    fi

    if command -v go &>/dev/null; then
        info "Go already installed: $(go version)"
        state_done "go"
        return 0
    fi

    step "Installing Go..."
    local GO_VERSION="1.24.5"
    local GO_DIR="$HOME/go"
    local GO_TAR="go${GO_VERSION}.linux-armv6l.tar.gz"

    cd /data/data/com.termux/files/usr/tmp
    curl -sL -o "$GO_TAR" "https://go.dev/dl/${GO_TAR}"
    tar xzf "$GO_TAR" -C "$HOME/"
    rm -f "$GO_TAR"

    export PATH="$GO_DIR/bin:$PATH"
    export GOROOT="$GO_DIR"

    if ! grep -q "GOROOT" "$HOME/.bashrc" 2>/dev/null; then
        echo "" >> "$HOME/.bashrc"
        echo "export GOROOT=$GO_DIR" >> "$HOME/.bashrc"
        echo 'export PATH="$GOROOT/bin:$PATH"' >> "$HOME/.bashrc"
    fi

    state_done "go"
    done_msg "Go installed: $(go version)"
}

# ---- Step 3: Create toolchain ----
create_toolchain() {
    if state_check "toolchain"; then
        skip "Toolchain"
        return 0
    fi

    local TOOLCHAIN="$HOME/android-arm-toolchain.cmake"

    if [ -f "$TOOLCHAIN" ]; then
        info "Toolchain already exists"
        state_done "toolchain"
        return 0
    fi

    step "Creating cross-compilation toolchain..."
    cat > "$TOOLCHAIN" << 'EOF'
set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR armv7l)
set(CMAKE_C_COMPILER arm-linux-androideabi-clang)
set(CMAKE_CXX_COMPILER arm-linux-androideabi-clang++)
set(CMAKE_ASM_COMPILER arm-linux-androideabi-clang)
set(CMAKE_AR arm-linux-androideabi-ar)
set(CMAKE_RANLIB arm-linux-androideabi-ranlib)
set(CMAKE_STRIP arm-linux-androideabi-strip)
set(CMAKE_C_FLAGS_INIT "-target armv7a-unknown-linux-android24 -mfloat-abi=softfp -mfpu=neon")
set(CMAKE_CXX_FLAGS_INIT "-target armv7a-unknown-linux-android24 -mfloat-abi=softfp -mfpu=neon")
set(CMAKE_FIND_ROOT_PATH /data/data/com.termux/files/usr)
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(ANDROID TRUE)
set(ANDROID_NATIVE_API_LEVEL 24)
set(CMAKE_ANDROID_NDK "")
set(CMAKE_ANDROID_ARCH_ABI armeabi-v7a)
set(CMAKE_SYSTEM_VERSION 24)
EOF

    state_done "toolchain"
    done_msg "Toolchain created"
}

# ---- Step 4: Build libcurl-impersonate ----
build_curl_impersonate() {
    if state_check "curl_impersonate"; then
        skip "libcurl-impersonate"
        return 0
    fi

    local BUILD_DIR="$HOME/curl-impersonate-build"
    local TOOLCHAIN="$HOME/android-arm-toolchain.cmake"
    local OUTPUT="$HOME/curl-impersonate-output"

    # Check if already built (from previous run)
    if [ -f "$OUTPUT/libcurl-impersonate.a" ]; then
        info "libcurl-impersonate already built"
        state_done "curl_impersonate"
        return 0
    fi

    step "Building libcurl-impersonate from source..."

    mkdir -p "$BUILD_DIR"
    cd "$BUILD_DIR"

    # Clone (skip if already cloned)
    if [ ! -d "curl-impersonate" ]; then
        info "Cloning curl-impersonate..."
        git clone --depth 1 https://github.com/lexiforest/curl-impersonate.git
    fi

    cd curl-impersonate

    # Configure (skip if already configured)
    if [ ! -f "build-android-arm/CMakeCache.txt" ]; then
        info "Configuring build..."
        cmake -S . -B build-android-arm \
            -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN" \
            -DCMAKE_BUILD_TYPE=Release \
            -DCMAKE_INSTALL_PREFIX="$OUTPUT" \
            -DANDROID=TRUE \
            -DANDROID_PLATFORM_LEVEL=24 \
            -DANDROID_ABI=armeabi-v7a
    fi

    # Build (always try to continue)
    info "Building (may take 10-15 minutes)..."
    cmake --build build-android-arm --parallel $(nproc)

    # Copy outputs
    info "Installing outputs..."
    mkdir -p "$OUTPUT"
    cp build-android-arm/deps/build/curl/lib/libcurl-impersonate.a "$OUTPUT/"
    cp build-android-arm/deps/build/boringssl/lib*.a "$OUTPUT/"
    cp build-android-arm/deps/build/nghttp2/lib/libnghttp2.a "$OUTPUT/"
    cp build-android-arm/deps/build/nghttp3/lib/libnghttp3.a "$OUTPUT/"
    cp build-android-arm/deps/build/ngtcp2/lib/libngtcp2.a "$OUTPUT/"
    cp build-android-arm/deps/build/ngtcp2/crypto/boringssl/libngtcp2_crypto_boringssl.a "$OUTPUT/"
    cp build-android-arm/deps/build/zlib/libz.a "$OUTPUT/"
    cp build-android-arm/deps/build/zstd/lib/libzstd.a "$OUTPUT/"
    cp build-android-arm/deps/build/brotli/lib*.a "$OUTPUT/"

    state_done "curl_impersonate"
    done_msg "libcurl-impersonate built"
}

# ---- Step 5: Install pip packages ----
install_pip_packages() {
    if state_check "pip_packages"; then
        skip "Pip packages"
        return 0
    fi

    step "Installing pip packages..."
    pip install --upgrade cffi certifi pycparser 2>&1 | tail -3

    state_done "pip_packages"
    done_msg "Pip packages"
}

# ---- Step 6: Install curl-cffi Python files ----
install_curl_cffi_python() {
    if state_check "curl_cffi_python"; then
        skip "curl-cffi Python files"
        return 0
    fi

    # Check if correct version installed
    local NEED_INSTALL=0
    if [ ! -f "$SITE_PACKAGES/curl_cffi/__init__.py" ]; then
        NEED_INSTALL=1
    else
        local INSTALLED_VER=$(python3 -c "import curl_cffi; print(curl_cffi.__version__)" 2>/dev/null)
        if [ "$INSTALLED_VER" != "$LATEST" ]; then
            info "Version mismatch: installed=$INSTALLED_VER, latest=$LATEST"
            NEED_INSTALL=1
        fi
    fi

    if [ "$NEED_INSTALL" -eq 0 ]; then
        info "curl-cffi ${LATEST} Python files already installed"
        state_done "curl_cffi_python"
        return 0
    fi

    step "Installing curl-cffi ${LATEST} Python files..."
    mkdir -p "$SITE_PACKAGES/curl_cffi"

    # Download and extract
    local TMPDIR=$(mktemp -d)
    cd "$TMPDIR"
    curl -sL -o curl_cffi.tar.gz "https://files.pythonhosted.org/packages/source/c/curl-cffi/curl_cffi-${LATEST}.tar.gz"
    tar xzf curl_cffi.tar.gz

    # Copy Python files
    find curl_cffi-${LATEST}/curl_cffi -name "*.py" | while read f; do
        rel=${f#curl_cffi-${LATEST}/curl_cffi/}
        dir=$(dirname "$rel")
        mkdir -p "$SITE_PACKAGES/curl_cffi/$dir"
        cp "$f" "$SITE_PACKAGES/curl_cffi/$dir/"
    done

    # Fix __version__.py to hardcode version (metadata may be stale)
    cat > "$SITE_PACKAGES/curl_cffi/__version__.py" << VERSION_EOF
__title__ = "curl_cffi"
__description__ = "Python http client with TLS fingerprint impersonation"
__version__ = "${LATEST}"

def _resolve_curl_version() -> str:
    from ._wrapper import ffi, lib
    return ffi.string(lib.curl_version()).decode()

__curl_version__ = _resolve_curl_version()
VERSION_EOF

    rm -rf "$TMPDIR"

    state_done "curl_cffi_python"
    done_msg "curl-cffi ${LATEST} Python files installed"
}

# ---- Step 7: Build wrapper ----
build_wrapper() {
    if state_check "wrapper"; then
        skip "Wrapper"
        return 0
    fi

    local OUTPUT="$HOME/curl-impersonate-output"
    local CFFI_SRC="$HOME/curl-cffi-build"

    # Check prerequisites
    if [ ! -f "$OUTPUT/libcurl-impersonate.a" ]; then
        error "libcurl-impersonate.a not found"
        return 1
    fi

    step "Building curl-cffi wrapper..."

    # Get source (download if missing or wrong version)
    local NEED_DOWNLOAD=0
    if [ ! -d "$CFFI_SRC" ] || [ -z "$(ls -A $CFFI_SRC 2>/dev/null)" ]; then
        NEED_DOWNLOAD=1
    else
        # Check if downloaded version matches latest
        local DOWNLOADED_VER=$(ls "$CFFI_SRC" | grep "curl_cffi-" | head -1 | sed 's/curl_cffi-//' | sed 's/\.tar\.gz//')
        if [ "$DOWNLOADED_VER" != "$LATEST" ]; then
            info "Version mismatch: downloaded=$DOWNLOADED_VER, latest=$LATEST"
            NEED_DOWNLOAD=1
        fi
    fi

    if [ "$NEED_DOWNLOAD" -eq 1 ]; then
        info "Downloading curl-cffi ${LATEST}..."
        rm -rf "$CFFI_SRC"
        mkdir -p "$CFFI_SRC"
        cd "$CFFI_SRC"
        curl -sL -o curl_cffi.tar.gz "https://files.pythonhosted.org/packages/source/c/curl-cffi/curl_cffi-${LATEST}.tar.gz"
        tar xzf curl_cffi.tar.gz
        rm -f curl_cffi.tar.gz
    fi

    # Find source directory
    local CFFI_DIR=$(find "$CFFI_SRC" -maxdepth 1 -name "curl_cffi-*" -type d | head -1)
    if [ -z "$CFFI_DIR" ]; then
        error "curl-cffi source not found"
        return 1
    fi
    cd "$CFFI_DIR"

    # Check if libs.json exists (required for build.py)
    if [ ! -f "libs.json" ]; then
        warn "libs.json missing, re-downloading source..."
        rm -rf "$CFFI_SRC"
        mkdir -p "$CFFI_SRC"
        cd "$CFFI_SRC"
        curl -sL -o curl_cffi.tar.gz "https://files.pythonhosted.org/packages/source/c/curl-cffi/curl_cffi-${LATEST}.tar.gz"
        tar xzf curl_cffi.tar.gz
        rm -f curl_cffi.tar.gz
        CFFI_DIR=$(find "$CFFI_SRC" -maxdepth 1 -name "curl_cffi-*" -type d | head -1)
        cd "$CFFI_DIR"
    fi

    # Patch libs.json (only if not already patched)
    if [ -f "libs.json" ]; then
        local NEEDS_PATCH=$(python3 -c "
import json
with open('libs.json') as f:
    data = json.load(f)
has = any(a.get('machine') == 'armv8l' and a.get('system') == 'Android' for a in data)
print('no' if has else 'yes')
" 2>/dev/null)

        if [ "$NEEDS_PATCH" = "yes" ]; then
            info "Patching libs.json for armv8l..."
            python3 -c "
import json, os
home = os.path.expanduser('~')
with open('libs.json') as f:
    data = json.load(f)
data.append({
    'system': 'Android', 'machine': 'armv8l', 'pointer_size': 32,
    'sysname': 'linux-android', 'link_type': 'static', 'libc': 'android',
    'obj_name': 'libcurl-impersonate.a', 'arch': 'arm',
    'libdir': f'{home}/curl-impersonate-output'
})
with open('libs.json', 'w') as f:
    json.dump(data, f, indent=4)
print('Patched libs.json')
" && info "libs.json patched" || error "Failed to patch libs.json"
        fi
    fi

    # Generate wrapper.c (only if not exists)
    if [ ! -f "curl_cffi/_wrapper.c" ]; then
        info "Generating wrapper source..."
        python3 scripts/build.py 2>/dev/null || true

        if [ ! -f "curl_cffi/_wrapper.c" ]; then
            error "Failed to generate wrapper.c"
            return 1
        fi
        info "wrapper.c generated"
    else
        info "wrapper.c already exists"
    fi

    # Compile wrapper (always recompile)
    info "Compiling wrapper..."
    mkdir -p "$SITE_PACKAGES/curl_cffi"
    local PYTHON_INC=$(python3 -c "import sysconfig; print(sysconfig.get_path('include'))")
    local PYTHON_VER=$(python3 -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")

    arm-linux-androideabi-clang -shared -o "$SITE_PACKAGES/curl_cffi/_wrapper.abi3.so" \
        curl_cffi/_wrapper.c \
        ffi/shim.c \
        -I include -I ffi -I "$PYTHON_INC" \
        -fPIC -DPy_LIMITED_API=0x00030e00 \
        -Wl,--whole-archive \
        "$OUTPUT/libcurl-impersonate.a" \
        "$OUTPUT/libssl.a" \
        "$OUTPUT/libcrypto.a" \
        "$OUTPUT/libngtcp2.a" \
        "$OUTPUT/libngtcp2_crypto_boringssl.a" \
        "$OUTPUT/libnghttp2.a" \
        "$OUTPUT/libnghttp3.a" \
        "$OUTPUT/libz.a" \
        "$OUTPUT/libzstd.a" \
        "$OUTPUT/libbrotlidec.a" \
        "$OUTPUT/libbrotlienc.a" \
        "$OUTPUT/libbrotlicommon.a" \
        -Wl,--no-whole-archive \
        -L"$LIB_DIR" \
        -lc++_shared -lpython$PYTHON_VER -lm -landroid-support -llog

    chmod 755 "$SITE_PACKAGES/curl_cffi/_wrapper.abi3.so"

    state_done "wrapper"
    done_msg "Wrapper built"
}

# ---- Verify installation ----
verify() {
    step "Verifying installation..."
    if python3 -c "
from curl_cffi import requests
r = requests.get('https://httpbin.org/headers', impersonate='chrome')
assert 'Chrome' in r.json()['headers'].get('User-Agent', '')
import curl_cffi
print(f'curl-cffi {curl_cffi.__version__}')
print(f'libcurl {curl_cffi.__curl_version__}')
" 2>&1; then
        done_msg "Installation verified!"
        return 0
    else
        error "Verification failed"
        return 1
    fi
}

# ---- Full update ----
update_full() {
    echo ""
    step "Full update with impersonation support..."
    echo ""

    # Show current state
    state_list
    echo ""

    # Run all steps (each skips if done)
    install_build_deps
    install_go
    create_toolchain
    build_curl_impersonate
    install_pip_packages
    install_curl_cffi_python
    build_wrapper

    echo ""
    state_list
    echo ""

    verify
}

# ---- Reset state (force rebuild) ----
reset_state() {
    state_clear
    info "Build state cleared. Next run will rebuild everything."
}

# ---- Show help ----
show_help() {
    echo ""
    echo "╔══════════════════════════════════════════════════════╗"
    echo "║  curl-cffi Updater for 32-bit Android ARM           ║"
    echo "║  Smart build - skips completed steps                ║"
    echo "╚══════════════════════════════════════════════════════╝"
    echo ""
    echo "Usage: ./update.sh [option]"
    echo ""
    echo "Options:"
    echo "  (no args)   Check for updates"
    echo "  --pip       Update via pip (fast, no impersonation)"
    echo "  --full      Full rebuild with impersonation"
    echo "  --reset     Clear build state (force full rebuild)"
    echo "  --status    Show build state"
    echo "  --version   Show current and latest versions"
    echo "  --help      Show this help"
    echo ""
    echo "Examples:"
    echo "  ./update.sh              # Check if update available"
    echo "  ./update.sh --full       # Build (skips completed steps)"
    echo "  ./update.sh --reset      # Clear state, rebuild everything"
    echo "  ./update.sh --status     # Show what's been built"
    echo ""
}

# ---- Main ----
main() {
    echo ""
    echo "╔══════════════════════════════════════════════════════╗"
    echo "║  curl-cffi Updater for 32-bit Android ARM           ║"
    echo "╚══════════════════════════════════════════════════════╝"
    echo ""

    detect_env

    case "${1:-}" in
        --help|-h)
            show_help
            ;;
        --pip)
            check_current
            step "Updating via pip..."
            pip install --upgrade curl-cffi cffi certifi pycparser 2>&1 | tail -5
            info "✅ pip update complete"
            ;;
        --full)
            check_current
            check_latest
            update_full
            ;;
        --reset)
            reset_state
            ;;
        --status)
            state_list
            ;;
        --version)
            check_current
            check_latest
            if [ "$CURRENT" = "$LATEST" ]; then
                info "✅ You're on the latest version!"
            else
                warn "Update available: $CURRENT → $LATEST"
            fi
            ;;
        *)
            check_current
            check_latest
            state_list
            if [ "$CURRENT" != "$LATEST" ]; then
                echo ""
                warn "Update available: $CURRENT → $LATEST"
                echo "  Run: ./update.sh --full"
            fi
            ;;
    esac
}

main "$@"
