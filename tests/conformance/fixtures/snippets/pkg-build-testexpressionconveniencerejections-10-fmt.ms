# conform: tags=formatter,match,optional,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/build/expression_conveniences_test.go:21 TestExpressionConvenienceRejections
def f(x: Optional[Int]) -> Unit:
    let y = match x:
        case some(n): n
        case none: "missing"
