// conform: tags=diagnostics,tier-core
// conform: phase=check
// conform: origin=pkg/checker/hints_test.go:44 TestDiagnosticsStateCauseAndFix
fn f() Int {
	return [1, 2].length
}
// expect-error: MS3001 5:19 expected Int, found fn() Int (in the return value); this is a method, not a property; call it with parentheses to get its Int result, as in `xs.length()`
// expect-fix: 5:12-5:25 "[1, 2].length()"
