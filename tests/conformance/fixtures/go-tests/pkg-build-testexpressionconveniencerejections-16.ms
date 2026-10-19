# conform: tags=match,optional,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/build/expression_conveniences_test.go:27 TestExpressionConvenienceRejections
fn f(x: Optional[Int]) Int:
    return match x:
        some(n):
            n
            n + 1
        none: 0
