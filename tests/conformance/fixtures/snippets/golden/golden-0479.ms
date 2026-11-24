// conform: tags=diagnostics
// conform: phase=check
import CompressionFormat, compress from "@std/compress.ms"

fn explicit() Void {
	data := "".to_bytes()
	compress(data, "gzip", 6)
	compress(data, "zlib", 0, max_bytes: null)
	compress(data, "deflate", 9, max_bytes: 100)
	CompressionFormat.Gzip.compress(data, 6)
	CompressionFormat.Zlib.compress(data, 0, max_bytes: null)
	CompressionFormat.Deflate.compress(data, 9, max_bytes: 100)
}
