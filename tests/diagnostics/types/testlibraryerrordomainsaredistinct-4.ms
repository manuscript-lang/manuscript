// conform: tags=diagnostics,formatter,modules,stdlib-encoding,tier-stdlib,try-result
// conform: phase=check,parse
// conform: origin=pkg/build/library_test.go:54 TestLibraryErrorDomainsAreDistinct
import hex_decode from "@std/data/encoding.ms"

fn wrong() Void! {
	bytes := hex_decode(text: "ff", max_bytes: 1)?
	return ok(value: void)
}
// expect-error: MS3000 7:5 local binding bytes is never read; remove it, use it, or name it with a leading '_' to ignore it
