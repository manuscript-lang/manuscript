// conform: tags=diagnostics,tier-core,try-result
// conform: phase=check
// conform: origin=pkg/build/library_test.go:48 TestLibraryErrorDomainsAreDistinct
fn wrong() Void! {
	return error(cause: Error("encoding: invalid data", kind: "EBADMSG"))
}
// expect-exit: 0
