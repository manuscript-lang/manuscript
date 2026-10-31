# conform: tags=diagnostics,tier-core,try-result
# conform: phase=check
# conform: origin=pkg/build/expression_conveniences_test.go:25 TestExpressionConvenienceRejections
fn p() Int!:
    return ok(1)

fn f() Int:
    return p()
