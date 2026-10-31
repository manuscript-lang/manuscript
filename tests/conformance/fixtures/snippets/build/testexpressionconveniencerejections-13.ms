# conform: tags=diagnostics,match,optional,tier-core,try-result
# conform: phase=check
# conform: origin=pkg/build/expression_conveniences_test.go:24 TestExpressionConvenienceRejections
fn p() Int!:
    return ok(1)

fn f(x: Int?) Unit!:
    match x:
        n:
            try p()
            return ok(unit)
        none: return ok(unit)
