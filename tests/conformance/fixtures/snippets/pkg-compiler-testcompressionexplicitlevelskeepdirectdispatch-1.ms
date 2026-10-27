# conform: tags=diagnostics,modules,stdlib-compress,tier-stdlib
# conform: phase=check
# conform: origin=pkg/compiler/compression_defaults_test.go:36 TestCompressionExplicitLevelsKeepDirectDispatch
from "@std/archive.ms" import compress, CompressionFormat

def explicit() -> Unit:
    let data = "".to_bytes()
    let _ = compress(data, "gzip", 6)
    let _ = compress(data, "zlib", 0, max_bytes: none)
    let _ = compress(data, "deflate", 9, max_bytes: 100)
    let _ = CompressionFormat.Gzip.compress(data, 6)
    let _ = CompressionFormat.Zlib.compress(data, 0, max_bytes: none)
    let _ = CompressionFormat.Deflate.compress(data, 9, max_bytes: 100)
