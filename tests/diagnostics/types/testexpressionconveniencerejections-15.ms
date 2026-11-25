// conform: tags=diagnostics,formatter,optional,tier-core
// conform: phase=check,parse
// conform: origin=pkg/build/expression_conveniences_test.go:26 TestExpressionConvenienceRejections
fn f(x Int?) Int {
	return x
}
// expect-error: MS3001 5:12 expected Int, found Int? (in the return value); Int? may be absent; test it first with 'if x != null', or give a default with 'x or default'
