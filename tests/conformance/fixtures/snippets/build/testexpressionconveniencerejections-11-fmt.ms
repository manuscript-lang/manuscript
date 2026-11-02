# conform: tags=formatter,match,optional,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/build/expression_conveniences_test.go:22 TestExpressionConvenienceRejections
fn f(x: Int?) Int:
    return match x:
        n: n
        none: return "missing"
