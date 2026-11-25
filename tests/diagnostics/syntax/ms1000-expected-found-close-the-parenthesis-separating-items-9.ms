// conform: tags=diagnostics
// conform: phase=check
encode fn(data: Bytes, level: Int, max_bytes: Int?) Result[Bytes, CompressionError] = CompressionFormat.Gzip.compress
    encode("".to_bytes())
// expect-error: MS1000 3:15-3:16 expected ')', found ':'; close the parenthesis, separating items with commas
