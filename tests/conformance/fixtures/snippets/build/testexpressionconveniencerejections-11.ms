// conform: tags=diagnostics,formatter,match,optional,tier-core
// conform: phase=check,parse
// conform: origin=pkg/build/expression_conveniences_test.go:22 TestExpressionConvenienceRejections
fn f(x Int?) Int {
	return match x {
		n => n
		null => return "missing"
	}
}
// expect-error: MS3001 7:24 expected Int, found String (in the return value)
