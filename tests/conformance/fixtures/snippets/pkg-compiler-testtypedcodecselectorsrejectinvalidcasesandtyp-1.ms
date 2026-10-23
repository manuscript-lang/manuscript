# conform: tags=diagnostics,modules,stdlib-string,tier-stdlib
# conform: phase=check
# conform: origin=pkg/compiler/codec_selectors_test.go:10 TestTypedCodecSelectorsRejectInvalidCasesAndTypes
import NormalizationForm from "@std/string.ms"

fn wrong() Unit:
    let form = NormalizationForm.NFC
