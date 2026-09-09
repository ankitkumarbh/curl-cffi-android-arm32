__title__ = "curl_cffi"
__description__ = "Python http client with TLS fingerprint impersonation"
__version__ = "0.16.3"

def _resolve_curl_version() -> str:
    from ._wrapper import ffi, lib
    return ffi.string(lib.curl_version()).decode()

__curl_version__ = _resolve_curl_version()
