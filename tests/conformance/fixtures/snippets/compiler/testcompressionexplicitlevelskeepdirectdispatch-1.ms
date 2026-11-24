// conform: tags=diagnostics,modules,stdlib-compress,tier-stdlib
// conform: phase=check
// conform: origin=pkg/compiler/compression_defaults_test.go:36 TestCompressionExplicitLevelsKeepDirectDispatch
import CompressOptions, CompressionFormat, compress from "@std/io/archive.ms"

fn explicit() Void {
	data := "".to_bytes()
	void compress(data, CompressionFormat.Gzip, CompressOptions(level: 6))
	void compress(data, CompressionFormat.Zlib, CompressOptions(level: 0))
	void compress(
		data,
		CompressionFormat.Deflate,
		CompressOptions(level: 9, max_bytes: 100),
	)
}
