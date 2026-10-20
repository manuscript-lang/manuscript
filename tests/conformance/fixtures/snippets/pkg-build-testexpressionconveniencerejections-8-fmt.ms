# conform: tags=formatter,parser,strings,tier-core
# conform: phase=parse
# conform: origin=pkg/build/expression_conveniences_test.go:19 TestExpressionConvenienceRejections
fn f() String: return "a" - "b"
