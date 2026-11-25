// conform: tags=diagnostics,formatter,tier-core,try-result
// conform: phase=check,parse
// conform: origin=pkg/build/expression_conveniences_test.go:25 TestExpressionConvenienceRejections
fn p() Int! {
	return ok(1)
}

fn f() Int {
	return p()
}
// expect-error: MS3001 9:12 expected Int, found Result[Int, Error] (in the return value); unwrap it with a trailing '?' inside a function that returns a compatible Result, with 'if value := x', or with '.get()'
