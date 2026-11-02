# conform: tags=formatter,match,optional,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/build/expression_conveniences_test.go:20 TestExpressionConvenienceRejections
fn f(x: Int?) Int:
    return match x:
        n: n
