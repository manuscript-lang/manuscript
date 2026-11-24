// conform: tags=formatter,modules,parser,stdlib-crypto,tier-stdlib
// conform: phase=parse
// conform: origin=pkg/compiler/codec_selectors_test.go:32 TestTypedCodecSelectorsRejectInvalidCasesAndTypes
import HashAlgorithm from "@std/crypto/crypto.ms"

fn choose(algorithm HashAlgorithm) Void:
    return

fn wrong() Void:
    choose("sha256")
