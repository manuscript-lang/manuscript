# conform: tags=formatter,modules,parser,stdlib-compress,tier-stdlib
# conform: phase=parse
# conform: origin=pkg/compiler/codec_selectors_test.go:24 TestTypedCodecSelectorsRejectInvalidCasesAndTypes
from "@std/archive.ms" import CompressionFormat

def wrong() -> Unit:
    let format = CompressionFormat.GZip
