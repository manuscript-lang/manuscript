# conform: tags=formatter,modules,parser,stdlib-crypto,tier-stdlib
# conform: phase=parse
# conform: origin=pkg/compiler/codec_selectors_test.go:20 TestTypedCodecSelectorsRejectInvalidCasesAndTypes
from "@std/crypto.ms" import HashAlgorithm

def wrong() -> Unit:
    let algorithm = HashAlgorithm.Sha257
