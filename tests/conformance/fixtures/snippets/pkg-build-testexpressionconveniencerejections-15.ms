# conform: tags=diagnostics,optional,tier-core
# conform: phase=check
# conform: origin=pkg/build/expression_conveniences_test.go:26 TestExpressionConvenienceRejections
def f(x: Optional[Int]) -> Int:
    return x
