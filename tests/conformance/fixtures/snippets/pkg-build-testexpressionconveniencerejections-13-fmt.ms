# conform: tags=formatter,match,optional,parser,tier-core,try-result
# conform: phase=parse
# conform: origin=pkg/build/expression_conveniences_test.go:24 TestExpressionConvenienceRejections
def p() -> Result[Int, Error]:
    return ok(1)

def f(x: Optional[Int]) -> Result[Unit, Error]:
    match x:
        case some(n):
            try p()
            return ok(())
        case none: return ok(())
