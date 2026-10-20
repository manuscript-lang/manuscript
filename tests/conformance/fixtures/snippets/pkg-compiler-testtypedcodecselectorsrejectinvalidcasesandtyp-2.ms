# conform: tags=diagnostics,modules,stdlib-string,tier-stdlib
# conform: phase=check
# conform: origin=pkg/compiler/codec_selectors_test.go:14 TestTypedCodecSelectorsRejectInvalidCasesAndTypes
import NormalizationForm from "@std/string.ms"
fn choose(form: NormalizationForm) Unit:
    return unit
fn wrong() Unit:
    choose("NFC")
