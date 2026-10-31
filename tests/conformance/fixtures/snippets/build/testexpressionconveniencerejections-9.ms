# conform: tags=diagnostics,match,optional,tier-core
# conform: phase=check
# conform: origin=pkg/build/expression_conveniences_test.go:20 TestExpressionConvenienceRejections
fn f(x: Int?) Int:
    return match x:
        n: n
