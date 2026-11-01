# conform: tags=formatter,modules,parser,stdlib-archive,tier-stdlib
# conform: phase=parse
# conform: origin=pkg/compiler/codec_selectors_test.go:28 TestTypedCodecSelectorsRejectInvalidCasesAndTypes
import ArchiveFormat from "@std/io/archive.ms"

fn wrong() Unit:
    let format = ArchiveFormat.TAR
