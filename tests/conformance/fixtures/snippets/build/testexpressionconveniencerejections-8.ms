// conform: tags=diagnostics,strings,tier-core
// conform: phase=check
// conform: origin=pkg/build/expression_conveniences_test.go:19 TestExpressionConvenienceRejections
fn f() String => return "a" - "b"
// expect-error: MS3000 4:29 arithmetic requires numeric operands
