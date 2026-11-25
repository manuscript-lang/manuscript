// conform: tags=diagnostics,formatter,modules,stdlib-compress,tier-stdlib
// conform: phase=check,parse
// conform: origin=pkg/compiler/codec_selectors_test.go:24 TestTypedCodecSelectorsRejectInvalidCasesAndTypes
import CompressionFormat from "@std/io/archive.ms"

fn wrong() Void {
	format := CompressionFormat.GZip
}
// expect-error: MS2001 7:33 unknown or non-nullary alternative case GZip of CompressionFormat; cases: Deflate, Gzip, Zlib (cases with payloads need call syntax)
