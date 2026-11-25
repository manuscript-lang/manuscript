// conform: tags=diagnostics,formatter,match,optional,tier-core
// conform: phase=check,parse
// conform: origin=pkg/build/expression_conveniences_test.go:23 TestExpressionConvenienceRejections
fn f(x Int?) Int {
	y := match x {
		n => n
		null => 0
	}

	return n
}
// expect-error: MS2001 10:12 unknown binding n; declare it with 'n := ...' before use, define 'fn n(...) T { ... }', or import it from a module
