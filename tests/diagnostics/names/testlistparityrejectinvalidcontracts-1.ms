// conform: tags=closures,diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=pkg/compiler/list_parity_test.go:15 TestListParityRejectInvalidContracts
fn wrong() Int {
	values := [fn() Int => 1]
	return values.distinct().length()
}
// expect-error: MS2001 6:19 unknown or ambiguous member distinct on List[fn() Int]; distinct requires fn() Int to be Equal; fn() Int does not satisfy Equal; use a type that implements it
