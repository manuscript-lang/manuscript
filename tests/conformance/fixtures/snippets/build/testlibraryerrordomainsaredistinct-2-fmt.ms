// conform: tags=formatter,parser,tier-core,try-result
// conform: phase=parse
// conform: origin=pkg/build/library_test.go:48 TestLibraryErrorDomainsAreDistinct
fn wrong() Void! {
	return error(cause: Error("encoding: invalid data", kind: "EBADMSG"))
}
