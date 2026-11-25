// conform: tags=diagnostics,generics,tier-core
// conform: phase=check
// conform: origin=pkg/checker/hints_test.go:29 TestDiagnosticsStateCauseAndFix
fn g[T](x T) Int {
	return 0
}

fn f() Int {
	return g()
}
// expect-error: MS3080 9:12 cannot infer type argument T for g; write g[T](...) with an explicit type for T; call arguments and the expected result must determine every type parameter
