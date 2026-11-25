// conform: tags=diagnostics,tier-core
// conform: phase=check
// conform: origin=pkg/checker/interface_hints_test.go:25 TestInterfaceAndReceiverHints
fn error_method() Void {
	method := Error.message
}
// expect-error: MS2001 5:21 Error has no member message; a type name is followed only by an enum case
