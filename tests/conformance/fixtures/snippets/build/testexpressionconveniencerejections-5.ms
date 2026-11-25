// conform: tags=diagnostics,tier-core
// conform: phase=check
// conform: origin=pkg/build/expression_conveniences_test.go:16 TestExpressionConvenienceRejections
fn f() Void => xs := List()
// expect-error: MS3080 4:22 cannot infer constructor type argument T; write the type arguments, e.g. Box[Int](...), or annotate the binding
