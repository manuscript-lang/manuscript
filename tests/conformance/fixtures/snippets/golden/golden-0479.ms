// conform: tags=diagnostics
// conform: phase=check
import compress, CompressionFormat from "@std/compress.ms"
fn explicit() Unit:
    data := "".to_bytes()
    compress(data, "gzip", 6)
    compress(data, "zlib", 0, max_bytes: none)
    compress(data, "deflate", 9, max_bytes: 100)
    CompressionFormat.Gzip.compress(data, 6)
    CompressionFormat.Zlib.compress(data, 0, max_bytes: none)
    CompressionFormat.Deflate.compress(data, 9, max_bytes: 100)
