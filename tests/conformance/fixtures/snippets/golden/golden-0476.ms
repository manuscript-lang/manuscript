// conform: tags=diagnostics
// conform: phase=check
encode: fn(data: Bytes, format: String, level: Int, max_bytes: Int?) Result[Bytes, CompressionError] = compress
    encode("".to_bytes(), "gzip")