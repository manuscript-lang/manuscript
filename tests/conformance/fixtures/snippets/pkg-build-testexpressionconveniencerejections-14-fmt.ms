# conform: tags=formatter,parser,tier-core,try-result
# conform: phase=parse
# conform: origin=pkg/build/expression_conveniences_test.go:25 TestExpressionConvenienceRejections
def p() -> Result[Int, Error]:
    return ok(1)

def f() -> Int:
    return p()
