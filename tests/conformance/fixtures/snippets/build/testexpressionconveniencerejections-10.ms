# conform: tags=diagnostics,match,optional,tier-core
# conform: phase=check
# conform: origin=pkg/build/expression_conveniences_test.go:21 TestExpressionConvenienceRejections
fn f(x: Int?) Unit:
    let y = match x:
        n: n
        none: "missing"
