# conform: tags=formatter,optional,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/build/expression_conveniences_test.go:26 TestExpressionConvenienceRejections
fn f(x: Optional[Int]) Int:
    return x
