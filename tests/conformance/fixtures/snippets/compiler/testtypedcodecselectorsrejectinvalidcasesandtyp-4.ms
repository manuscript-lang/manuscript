# conform: tags=diagnostics,modules,stdlib-compress,tier-stdlib
# conform: phase=check
# conform: origin=pkg/compiler/codec_selectors_test.go:24 TestTypedCodecSelectorsRejectInvalidCasesAndTypes
import CompressionFormat from "@std/io/archive.ms"

fn wrong() Unit:
    let format = CompressionFormat.GZip
