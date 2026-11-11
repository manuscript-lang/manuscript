// conform: tags=diagnostics
// conform: phase=check
f: fn(data: Bytes, url_safe: Bool) String = base64_encode
    f(Bytes([]))