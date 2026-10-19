# conform: tags=diagnostics,strings,tier-core
# conform: phase=check
# conform: origin=pkg/build/expression_conveniences_test.go:18 TestExpressionConvenienceRejections
fn f() String: return "a" + 1
