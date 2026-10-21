# conform: tags=diagnostics,modules,stdlib-compress,tier-stdlib
# conform: phase=check
# conform: origin=pkg/compiler/compression_defaults_test.go:36 TestCompressionExplicitLevelsKeepDirectDispatch
import {compress, CompressionFormat} from "@std/archive.ms"
fn explicit() Unit:
    let data = "".to_bytes()
    compress(data, "gzip", 6)
    compress(data, "zlib", 0, max_bytes: none)
    compress(data, "deflate", 9, max_bytes: 100)
    CompressionFormat.Gzip.compress(data, 6)
    CompressionFormat.Zlib.compress(data, 0, max_bytes: none)
    CompressionFormat.Deflate.compress(data, 9, max_bytes: 100)
