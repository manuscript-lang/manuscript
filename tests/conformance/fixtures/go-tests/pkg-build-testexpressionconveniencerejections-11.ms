# conform: tags=diagnostics,match,optional,tier-core
# conform: phase=check
# conform: origin=pkg/build/expression_conveniences_test.go:22 TestExpressionConvenienceRejections
fn f(x: Optional[Int]) Int:
    return match x:
        some(n): n
        none: return "missing"
