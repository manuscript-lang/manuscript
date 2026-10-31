# conform: tags=formatter,match,optional,parser,tier-core,try-result
# conform: phase=parse
# conform: origin=pkg/build/expression_conveniences_test.go:24 TestExpressionConvenienceRejections
fn p() Result[Int, Error]:
    return ok(1)

fn f(x: Int?) Result[Unit, Error]:
    match x:
        n:
            try p()
            return ok(unit)
        none: return ok(unit)
