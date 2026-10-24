# conform: tags=control-flow,formatter,parser,tier-core,try-result
# conform: phase=parse
# conform: origin=pkg/compiler/result_bounds_test.go:57 TestSuccessfulResultBoundsRejectDifferentReturns
def affine(n: Int = 0) -> Result[Int, Cause]:
    if n < 0: return error(Cause("negative"))

    return ok(n + 1)
