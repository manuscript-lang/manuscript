# conform: tags=diagnostics,modules,stdlib-string,tier-stdlib
# conform: phase=check
# conform: origin=pkg/compiler/codec_selectors_test.go:10 TestTypedCodecSelectorsRejectInvalidCasesAndTypes
from "@std/string.ms" import NormalizationForm

def wrong() -> Unit:
    let form = NormalizationForm.NFC
