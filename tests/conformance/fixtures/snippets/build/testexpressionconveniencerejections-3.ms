// conform: tags=diagnostics,formatter,lists,tier-core
// conform: phase=check,parse
// conform: origin=pkg/build/expression_conveniences_test.go:14 TestExpressionConvenienceRejections
fn f(xs List[Int]) Int => return xs["0"]
// expect-error: MS3001 4:37 expected Int, found String
