# conform: tags=control-flow,formatter,match,optional,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/build/expression_conveniences_test.go:13 TestExpressionConvenienceRejections
def f(x: Optional[Int]) -> Int:
    while True:
        while (
            match x:
                case some(n): True
                case none: break
        ):
            break
