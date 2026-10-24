# conform: tags=control-flow,formatter,parser,tier-core,try-result
# conform: phase=parse
# conform: origin=pkg/compiler/result_bounds_test.go:61 TestSuccessfulResultBoundsRejectDifferentReturns
def affine(n: Int) -> Result[Int, Cause]:
    if n < 0: return ok(9223372036854775807)

    return ok(n + 1)
