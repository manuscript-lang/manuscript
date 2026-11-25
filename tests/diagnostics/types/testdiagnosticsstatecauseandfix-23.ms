// conform: tags=diagnostics,formatter,numbers,tier-core
// conform: phase=check,parse
// conform: origin=pkg/checker/hints_test.go:42 TestDiagnosticsStateCauseAndFix
fn f() Float {
	x Float := 3
	return x
}
// expect-error: MS3001 5:16 expected Float, found Int (in the initializer of 'x'); Int does not convert to Float implicitly; write a Float literal such as 3.0, or call to_float() on an Int value
// expect-fix: 5:16-5:17 "3.0"
