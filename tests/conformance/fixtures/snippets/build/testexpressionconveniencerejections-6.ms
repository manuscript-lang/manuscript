// conform: tags=diagnostics,formatter,lists,tier-core
// conform: phase=check,parse
// conform: origin=pkg/build/expression_conveniences_test.go:17 TestExpressionConvenienceRejections
fn f() Void => xs := List[Int](1)
// expect-error: MS3000 4:32 too many positional arguments; every parameter is already supplied, so remove this argument
