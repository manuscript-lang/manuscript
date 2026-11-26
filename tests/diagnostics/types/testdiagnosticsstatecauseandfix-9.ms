// conform: tags=diagnostics,formatter,generics,tier-core
// conform: phase=check,parse
// conform: origin=pkg/checker/hints_test.go:28 TestDiagnosticsStateCauseAndFix
fn id[T](x T) T {
	return x
}

fn f() Int {
	g := id
	return g(1)
}
// expect-error: MS3000 9:10 a generic function value requires explicit specialization; write id[Type] or call it with arguments
