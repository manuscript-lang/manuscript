// conform: tags=diagnostics,formatter,modules,stdlib-string,tier-stdlib
// conform: phase=check,parse
// conform: origin=pkg/compiler/codec_selectors_test.go:10 TestTypedCodecSelectorsRejectInvalidCasesAndTypes
import NormalizationForm from "@std/string.ms"

fn wrong() Void {
	form := NormalizationForm.NFC
}
// expect-error: MS2001 7:31 unknown or non-nullary alternative case NFC of NormalizationForm; cases: Nfc, Nfd, Nfkc, Nfkd (cases with payloads need call syntax)
