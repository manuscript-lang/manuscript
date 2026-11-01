# conform: tags=formatter,modules,parser,stdlib-compress,stdlib-crypto,tier-stdlib
# conform: phase=parse
# conform: origin=pkg/compiler/codec_selectors_test.go:38 TestTypedCodecSelectorsRejectInvalidCasesAndTypes
import HashAlgorithm from "@std/crypto.ms"
import CompressionFormat from "@std/io/archive.ms"

fn choose(algorithm: HashAlgorithm) Unit:
    return unit

fn wrong() Unit:
    choose(CompressionFormat.Gzip)
