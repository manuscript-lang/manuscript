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
