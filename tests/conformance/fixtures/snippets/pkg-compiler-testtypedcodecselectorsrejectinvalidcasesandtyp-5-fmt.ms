# conform: tags=formatter,modules,parser,stdlib-archive,tier-stdlib
# conform: phase=parse
# conform: origin=pkg/compiler/codec_selectors_test.go:28 TestTypedCodecSelectorsRejectInvalidCasesAndTypes
from "@std/archive.ms" import ArchiveFormat

def wrong() -> Unit:
    let format = ArchiveFormat.TAR
