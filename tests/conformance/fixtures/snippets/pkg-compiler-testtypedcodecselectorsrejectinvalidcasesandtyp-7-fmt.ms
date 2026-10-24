# conform: tags=formatter,modules,parser,stdlib-compress,stdlib-crypto,tier-stdlib
# conform: phase=parse
# conform: origin=pkg/compiler/codec_selectors_test.go:38 TestTypedCodecSelectorsRejectInvalidCasesAndTypes
from "@std/crypto.ms" import HashAlgorithm
from "@std/archive.ms" import CompressionFormat

def choose(algorithm: HashAlgorithm) -> Unit:
    return ()

def wrong() -> Unit:
    choose(CompressionFormat.Gzip)
