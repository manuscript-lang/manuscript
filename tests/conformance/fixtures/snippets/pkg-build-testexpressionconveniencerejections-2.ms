# conform: tags=control-flow,diagnostics,match,optional,tier-core
# conform: phase=check
# conform: origin=pkg/build/expression_conveniences_test.go:13 TestExpressionConvenienceRejections
fn f(x: Optional[Int]) Int:
    while true:
        while (
            match x:
                some(n): true
                none: break
        ):
            break
