# conform: tags=diagnostics,modules,stdlib-archive,tier-stdlib
# conform: phase=check
# conform: origin=pkg/compiler/codec_selectors_test.go:28 TestTypedCodecSelectorsRejectInvalidCasesAndTypes
from "@std/archive.ms" import ArchiveFormat

def wrong() -> Unit:
    let format = ArchiveFormat.TAR
