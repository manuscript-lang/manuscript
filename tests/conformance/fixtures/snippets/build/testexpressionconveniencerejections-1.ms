// conform: tags=diagnostics,match,optional,tier-core
// conform: phase=check
// conform: origin=pkg/build/expression_conveniences_test.go:12 TestExpressionConvenienceRejections
fn optional(value Int = 1) Int => return value

fn required(value Int) Int => return value

fn call(x Int?) Int {
	chosen := match x {
		n => optional
		null => required
	}

	return chosen()
}
// expect-error: MS3003 14:12 missing argument 1: Int in call to chosen; pass it positionally, without a label
