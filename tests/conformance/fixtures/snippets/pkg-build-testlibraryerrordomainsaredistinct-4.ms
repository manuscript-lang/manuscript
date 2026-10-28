# conform: tags=diagnostics,modules,stdlib-encoding,tier-stdlib,try-result
# conform: phase=check
# conform: origin=pkg/build/library_test.go:54 TestLibraryErrorDomainsAreDistinct
import hex_decode from "@std/encoding.ms"

fn wrong() Result[Unit, JsonError]:
    let bytes = try hex_decode(text: "ff", max_bytes: 1)
    return ok(value: unit)
