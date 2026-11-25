// conform: tags=diagnostics
// conform: phase=check
f fn(data: Bytes, url_safe: Bool) String = base64_encode
    f(Bytes([]))
// expect-error: MS1000 3:10-3:11 expected ')', found ':'; close the parenthesis, separating items with commas
