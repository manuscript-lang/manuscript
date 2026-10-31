# conform: tags=formatter,modules,parser,stdlib-string,tier-stdlib
# conform: phase=parse
# conform: origin=pkg/compiler/codec_selectors_test.go:10 TestTypedCodecSelectorsRejectInvalidCasesAndTypes
import NormalizationForm from "@std/string.ms"

fn wrong() Unit:
    let form = NormalizationForm.NFC
