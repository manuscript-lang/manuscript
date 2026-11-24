// conform: tags=diagnostics,modules,stdlib-compress,stdlib-crypto,tier-stdlib
// conform: phase=check
// conform: origin=pkg/compiler/codec_selectors_test.go:38 TestTypedCodecSelectorsRejectInvalidCasesAndTypes
import (
	HashAlgorithm from "@std/crypto/crypto.ms",
	CompressionFormat from "@std/io/archive.ms",
)

fn choose(algorithm HashAlgorithm) Void {
	return
}

fn wrong() Void {
	choose(CompressionFormat.Gzip)
}
