# conform: tags=formatter,match,optional,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/build/expression_conveniences_test.go:21 TestExpressionConvenienceRejections
fn f(x: Optional[Int]) Unit:
    let y = match x:
        some(n): n
        none: "missing"
