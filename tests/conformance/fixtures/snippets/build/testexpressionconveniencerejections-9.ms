// conform: tags=diagnostics,match,optional,tier-core
// conform: phase=check
// conform: origin=pkg/build/expression_conveniences_test.go:20 TestExpressionConvenienceRejections
fn f(x Int?) Int {
	return match x {
		n => n
	}
}
// expect-error: MS3050 5:12 non-exhaustive match; missing cases: null, or add a final '_ => ...' arm; add the arms 'null => ...'
