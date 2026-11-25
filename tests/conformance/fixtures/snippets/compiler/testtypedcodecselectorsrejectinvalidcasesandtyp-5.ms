// conform: tags=diagnostics,formatter,modules,stdlib-archive,tier-stdlib
// conform: phase=check,parse
// conform: origin=pkg/compiler/codec_selectors_test.go:28 TestTypedCodecSelectorsRejectInvalidCasesAndTypes
import ArchiveFormat from "@std/io/archive.ms"

fn wrong() Void {
	format := ArchiveFormat.TAR
}
// expect-error: MS2001 7:29 unknown or non-nullary alternative case TAR of ArchiveFormat; cases: Tar, Zip (cases with payloads need call syntax)
