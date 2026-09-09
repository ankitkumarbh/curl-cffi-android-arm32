# curl-cffi 0.16.3 for 32-bit Android ARM

Pre-built `curl-cffi` with **full impersonation support** for 32-bit Android ARM (armv7l/armv8l) devices.

## What's Included

| Component | Version | Notes |
|-----------|---------|-------|
| curl-cffi | 0.16.3 | Python HTTP client with TLS fingerprint impersonation |
| libcurl-impersonate | 8.21.0 | Built from source with BoringSSL |
| BoringSSL | latest | TLS/SSL library (statically linked) |
| Python | 3.14 | Built and tested on Termux |

## Features

- ✅ **TLS Fingerprint Impersonation** - Chrome, Firefox, Safari, Edge, etc.
- ✅ **HTTP/2 & HTTP/3 (QUIC)** support
- ✅ **Brotli, Zstd** compression
- ✅ **All HTTP methods** - GET, POST, PUT, DELETE, etc.
- ✅ **Static linking** - No external libcurl dependency

## Requirements

- **32-bit Android ARM** device (armv7l/armv8l)
- **Python 3.10+** (built for 3.14, works on 3.10-3.14)
- **Termux** recommended

## Installation

```bash
# Download and extract
tar xzf curl-cffi-android-arm32.tar.gz
cd curl-cffi-android-arm32

# Make install script executable
chmod +x install.sh

# Run installer
./install.sh
```

## Usage

```python
from curl_cffi import requests

# Basic GET
r = requests.get('https://example.com')
print(r.status_code)

# Impersonate Chrome
r = requests.get('https://httpbin.org/headers', impersonate='chrome')
print(r.json()['headers']['User-Agent'])
# → Chrome/150.0.0.0 ...

# Impersonate Firefox
r = requests.get('https://httpbin.org/headers', impersonate='firefox')
print(r.json()['headers']['User-Agent'])
# → Firefox/147.0 ...

# Impersonate Safari
r = requests.get('https://httpbin.org/headers', impersonate='safari')
print(r.json()['headers']['User-Agent'])
# → Safari/605.1.15 ...

# POST with JSON
r = requests.post('https://httpbin.org/post', json={"key": "value"})
print(r.json())
```

## Supported Impersonation Targets

| Target | Browsers |
|--------|----------|
| `chrome` | Chrome 150 |
| `chrome110` | Chrome 110 |
| `chrome120` | Chrome 120 |
| `chrome131` | Chrome 131 |
| `firefox` | Firefox 147 |
| `firefox133` | Firefox 133 |
| `safari` | Safari 18.0 |
| `safari_ios` | Safari iOS 18.0 |
| `edge` | Edge 150 |
| `qq` | QQ Browser |
| `wechat` | WeChat Browser |

## Updating

When a new version is available:

```bash
# Check for updates
./update.sh

# Quick update (no impersonation rebuild)
./update.sh --pip

# Full update (rebuild impersonation from source, ~15 min)
./update.sh --full
```

| Method | Speed | Impersonation | When to use |
|--------|-------|---------------|-------------|
| `--pip` | Fast (~30s) | ❌ Lost | Quick bug fixes |
| `--full` | Slow (~15min) | ✅ Kept | New features, full update |

## Uninstallation

```bash
./uninstall.sh
```

## Building from Source

If you need to rebuild for a different Python version or architecture:

1. Install build dependencies:
   ```bash
   pkg install cmake ninja clang
   ```

2. Build libcurl-impersonate:
   ```bash
   git clone https://github.com/lexiforest/curl-impersonate
   cd curl-impersonate
   cmake -S . -B build -DCMAKE_TOOLCHAIN_FILE=<your-toolchain>
   cmake --build build
   ```

3. Build curl-cffi wrapper:
   ```bash
   pip install curl-cffi --no-binary=:all: --target build
   # Replace _wrapper.abi3.so with statically linked version
   ```

## Technical Details

This package statically links:
- libcurl-impersonate (with TLS fingerprint impersonation)
- BoringSSL (TLS/SSL)
- nghttp2, nghttp3, ngtcp2 (HTTP/2, HTTP/3)
- zlib, zstd, brotli (compression)

The resulting `_wrapper.abi3.so` (~19MB) contains all dependencies, requiring only
`libc++_shared.so` at runtime.

## License

curl-cffi is MIT licensed. See [LICENSE](https://rem.mit-license.org/) for details.
