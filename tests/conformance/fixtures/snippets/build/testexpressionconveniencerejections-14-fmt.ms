# conform: tags=formatter,parser,tier-core,try-result
# conform: phase=parse
# conform: origin=pkg/build/expression_conveniences_test.go:25 TestExpressionConvenienceRejections
fn p() Int!:
    return ok(1)

fn f() Int:
    return p()
