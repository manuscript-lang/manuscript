# conform: tags=diagnostics,modules,stdlib-crypto,tier-stdlib
# conform: phase=check
# conform: origin=pkg/compiler/codec_selectors_test.go:32 TestTypedCodecSelectorsRejectInvalidCasesAndTypes
from "@std/crypto.ms" import HashAlgorithm

def choose(algorithm: HashAlgorithm) -> Unit:
    return ()

def wrong() -> Unit:
    choose("sha256")
