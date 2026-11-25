// conform: tags=diagnostics,match,optional,tier-core,try-result
// conform: phase=check
// conform: origin=pkg/build/expression_conveniences_test.go:24 TestExpressionConvenienceRejections
fn p() Int! {
	return ok(1)
}

fn f(x Int?) Void! {
	match x {
		n => {
			p()?
			return ok()
		}
		null => return ok()
	}
}
// expect-error: MS3000 11:13 a standalone '?' requires a Void success value, found Int; use 'name := call()?' to keep the value or 'return call()?' to return it
