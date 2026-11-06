// conform: tags=diagnostics,modules,stdlib-compress,tier-stdlib
// conform: phase=check
// conform: origin=pkg/compiler/compression_defaults_test.go:36 TestCompressionExplicitLevelsKeepDirectDispatch
import compress, CompressionFormat, CompressOptions from "@std/io/archive.ms"

fn explicit() Unit:
    let data = "".to_bytes()
    let _ = compress(data, CompressionFormat.Gzip, CompressOptions(level: 6))
    let _ = compress(data, CompressionFormat.Zlib, CompressOptions(level: 0))
    let _ = compress(
        data, CompressionFormat.Deflate, CompressOptions(level: 9, max_bytes: 100)
    )
