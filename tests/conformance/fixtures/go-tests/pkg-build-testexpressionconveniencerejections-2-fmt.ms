# conform: tags=control-flow,formatter,match,optional,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/build/expression_conveniences_test.go:13 TestExpressionConvenienceRejections
fn f(x: Optional[Int]) Int:
    while true:
        while (match x:
            some(n): true
            none: break
        ):
            break
