# conform: tags=diagnostics,modules,stdlib-string,tier-stdlib
# conform: phase=check
# conform: origin=pkg/compiler/codec_selectors_test.go:14 TestTypedCodecSelectorsRejectInvalidCasesAndTypes
from "@std/string.ms" import NormalizationForm

def choose(form: NormalizationForm) -> Unit:
    return ()

def wrong() -> Unit:
    choose("NFC")
