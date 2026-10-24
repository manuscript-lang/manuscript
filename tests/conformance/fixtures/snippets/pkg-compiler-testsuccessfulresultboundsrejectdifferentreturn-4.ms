# conform: tags=control-flow,diagnostics,tier-core,try-result
# conform: phase=check
# conform: origin=pkg/compiler/result_bounds_test.go:69 TestSuccessfulResultBoundsRejectDifferentReturns
def affine(n: Int) -> Result[Int, Cause]:
    if n < 0: return error(Cause())

    return ok(n + 1)
