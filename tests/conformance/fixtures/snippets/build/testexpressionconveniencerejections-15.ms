# conform: tags=diagnostics,optional,tier-core
# conform: phase=check
# conform: origin=pkg/build/expression_conveniences_test.go:26 TestExpressionConvenienceRejections
fn f(x: Int?) Int:
    return x
