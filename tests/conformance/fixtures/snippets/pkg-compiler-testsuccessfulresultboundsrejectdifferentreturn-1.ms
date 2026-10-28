# conform: tags=control-flow,diagnostics,tier-core,try-result
# conform: phase=check
# conform: origin=pkg/compiler/result_bounds_test.go:57 TestSuccessfulResultBoundsRejectDifferentReturns
fn affine(n: Int = 0) Result[Int, Cause]:
    if n < 0: return error(Cause("negative"))

    return ok(n + 1)
