// conform: tags=diagnostics,faults,optional,tier-core
// conform: phase=check
// conform: origin=pkg/compiler/optional_test.go:62 TestOptionalMethodsRejectInvalidContracts
fn wrong(value Int?) Int {
	return value or "missing"
}
// expect-error: MS3000 5:18 `or` on Int? needs Int or Int? on the right, found String
