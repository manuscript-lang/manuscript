# conform: tags=formatter,modules,parser,stdlib-encoding,tier-stdlib,try-result
# conform: phase=parse
# conform: origin=pkg/build/library_test.go:54 TestLibraryErrorDomainsAreDistinct
from "@std/encoding.ms" import hex_decode

def wrong() -> Result[Unit, JsonError]:
    let bytes = try hex_decode(text: "ff", max_bytes: 1)
    return ok(value: ())
