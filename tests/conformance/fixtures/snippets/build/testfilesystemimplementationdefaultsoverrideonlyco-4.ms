// conform: tags=diagnostics,interfaces,testing,tier-core
// conform: phase=check
// conform: origin=pkg/build/filesystem_defaults_test.go:116 TestFilesystemImplementationDefaultsOverrideOnlyConcreteCalls
test "filesystem concrete overrides and interface defaults" {
	item := Override(false)
	view := FileSystem(item)
}
// expect-error: MS2001 5:13 unknown binding Override; declare it with 'Override := ...' before use, define 'fn Override(...) T { ... }', or import it from a module
// expect-error: MS2001 6:13 unknown binding FileSystem; declare it with 'FileSystem := ...' before use, define 'fn FileSystem(...) T { ... }', or import it from a module
