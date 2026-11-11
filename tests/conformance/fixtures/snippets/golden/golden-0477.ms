// conform: tags=diagnostics
// conform: phase=check
encode := forward(CompressionFormat.Gzip.compress)
    encode("".to_bytes())