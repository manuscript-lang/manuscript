// conform: tags=diagnostics
// conform: phase=check
import (
	CompressionFormat from "@std/compress.ms",
	HashAlgorithm from "@std/crypto/crypto.ms",
)

fn choose(algorithm HashAlgorithm) Void {
	return
}

fn wrong() Void {
	choose(CompressionFormat.Gzip)
}
// expect-error: MS2002 4:5-4:22 unknown standard module @std/compress.ms; CompressionFormat is exported by another standard module, so write: import CompressionFormat from "@std/io/archive.ms"
// expect-error: MS2001 13:12 unknown binding CompressionFormat; add: import CompressionFormat from "@std/io/archive.ms"
// expect-fix: 1:1-1:1 "import CompressionFormat from \"@std/io/archive.ms\"\n"
