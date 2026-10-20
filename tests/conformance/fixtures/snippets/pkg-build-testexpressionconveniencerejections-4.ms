# conform: tags=diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/build/expression_conveniences_test.go:15 TestExpressionConvenienceRejections
fn f() Int: return 1[0]
