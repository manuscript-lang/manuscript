// conform: tags=diagnostics
// conform: phase=check
encode fn(data: Bytes, format: String, level: Int, max_bytes: Int?) Result[Bytes, CompressionError] = compress
    encode("".to_bytes(), "gzip")
// expect-error: MS1000 3:15-3:16 expected ')', found ':'; close the parenthesis, separating items with commas
