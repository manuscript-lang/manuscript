// conform: tags=diagnostics,formatter,match,optional,tier-core
// conform: phase=check,parse
// conform: origin=pkg/build/expression_conveniences_test.go:21 TestExpressionConvenienceRejections
fn f(x Int?) Void {
	y := match x {
		n => n
		null => "missing"
	}
}
// expect-error: MS3001 7:17 expected Int, found String
