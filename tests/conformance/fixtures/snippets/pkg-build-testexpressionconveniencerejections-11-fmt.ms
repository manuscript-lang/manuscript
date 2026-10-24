# conform: tags=formatter,match,optional,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/build/expression_conveniences_test.go:22 TestExpressionConvenienceRejections
def f(x: Optional[Int]) -> Int:
    return match x:
        case some(n): n
        case none: return "missing"
