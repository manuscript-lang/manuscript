// conform: tags=diagnostics,faults,optional,tier-core
// conform: phase=check
// conform: origin=pkg/compiler/optional_test.go:65 TestOptionalMethodsRejectInvalidContracts
fn wrong(value Int?) Int {
	return value
}
// expect-error: MS3001 5:12 expected Int, found Int? (in the return value); Int? may be absent; test it first with 'if x != null', or give a default with 'x or default'
