# conform: tags=formatter,match,optional,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/build/expression_conveniences_test.go:23 TestExpressionConvenienceRejections
fn f(x: Int?) Int:
    let y = match x:
        n: n
        none: 0

    return n
