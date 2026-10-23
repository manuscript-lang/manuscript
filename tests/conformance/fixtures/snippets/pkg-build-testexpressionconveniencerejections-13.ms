# conform: tags=diagnostics,match,optional,tier-core,try-result
# conform: phase=check
# conform: origin=pkg/build/expression_conveniences_test.go:24 TestExpressionConvenienceRejections
fn p() Result[Int, Error]:
    return ok(1)

fn f(x: Optional[Int]) Result[Unit, Error]:
    match x:
        some(n):
            try p()
            return ok(unit)
        none: return ok(unit)
