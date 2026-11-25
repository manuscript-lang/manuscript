// conform: tags=formatter,modules,parser,stdlib-compress,tier-stdlib
// conform: phase=parse
// conform: origin=pkg/compiler/compression_defaults_test.go:36 TestCompressionExplicitLevelsKeepDirectDispatch
import CompressionFormat, compress from "@std/io/archive.ms"

fn explicit() Void {
	data := "".to_bytes()
	void compress(data, "gzip", 6)
	void compress(data, "zlib", 0, max_bytes: null)
	void compress(data, "deflate", 9, max_bytes: 100)
	void CompressionFormat.Gzip.compress(data, 6)
	void CompressionFormat.Zlib.compress(data, 0, max_bytes: null)
	void CompressionFormat.Deflate.compress(data, 9, max_bytes: 100)
}
