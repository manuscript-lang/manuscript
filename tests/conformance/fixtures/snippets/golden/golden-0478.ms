// conform: tags=diagnostics
// conform: phase=check
encode: fn(data: Bytes, level: Int, max_bytes: Int?) Result[Bytes, CompressionError] = CompressionFormat.Gzip.compress
    encode("".to_bytes())