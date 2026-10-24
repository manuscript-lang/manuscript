# conform: tags=control-flow,diagnostics,match,optional,tier-core
# conform: phase=check
# conform: origin=pkg/build/expression_conveniences_test.go:13 TestExpressionConvenienceRejections
def f(x: Optional[Int]) -> Int:
    while True:
        while (
            match x:
                case some(n): True
                case none: break
        ):
            break
