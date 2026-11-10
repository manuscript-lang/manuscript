// conform: tags=formatter,modules,parser,stdlib-compress,tier-stdlib
// conform: phase=parse
// conform: origin=pkg/compiler/compression_defaults_test.go:36 TestCompressionExplicitLevelsKeepDirectDispatch
import compress, CompressionFormat from "@std/io/archive.ms"

fn explicit() Unit:
    data := "".to_bytes()
    _ := compress(data, "gzip", 6)
    _ := compress(data, "zlib", 0, max_bytes: none)
    _ := compress(data, "deflate", 9, max_bytes: 100)
    _ := CompressionFormat.Gzip.compress(data, 6)
    _ := CompressionFormat.Zlib.compress(data, 0, max_bytes: none)
    _ := CompressionFormat.Deflate.compress(data, 9, max_bytes: 100)
