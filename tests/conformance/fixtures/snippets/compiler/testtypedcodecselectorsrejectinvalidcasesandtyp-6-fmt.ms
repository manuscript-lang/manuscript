# conform: tags=formatter,modules,parser,stdlib-crypto,tier-stdlib
# conform: phase=parse
# conform: origin=pkg/compiler/codec_selectors_test.go:32 TestTypedCodecSelectorsRejectInvalidCasesAndTypes
import HashAlgorithm from "@std/crypto.ms"

fn choose(algorithm: HashAlgorithm) Unit:
    return unit

fn wrong() Unit:
    choose("sha256")
