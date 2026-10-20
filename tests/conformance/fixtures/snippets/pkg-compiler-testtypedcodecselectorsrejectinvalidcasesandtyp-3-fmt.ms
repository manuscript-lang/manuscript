# conform: tags=formatter,modules,parser,stdlib-crypto,tier-stdlib
# conform: phase=parse
# conform: origin=pkg/compiler/codec_selectors_test.go:20 TestTypedCodecSelectorsRejectInvalidCasesAndTypes
import HashAlgorithm from "@std/crypto.ms"
fn wrong() Unit:
    let algorithm = HashAlgorithm.Sha257
