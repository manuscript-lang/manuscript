// conform: tags=diagnostics,modules,stdlib-string,tier-stdlib
// conform: phase=check
// conform: origin=pkg/compiler/codec_selectors_test.go:14 TestTypedCodecSelectorsRejectInvalidCasesAndTypes
import NormalizationForm from "@std/string.ms"

fn choose(form NormalizationForm) Void {
	return
}

fn wrong() Void {
	choose("NFC")
}
// expect-error: MS3001 11:12 expected NormalizationForm, found String (in argument 'form' of choose)
