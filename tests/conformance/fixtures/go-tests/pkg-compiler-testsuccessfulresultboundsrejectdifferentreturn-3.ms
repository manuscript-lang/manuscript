# conform: tags=control-flow,diagnostics,interpolation,tier-core,try-result
# conform: phase=check
# conform: origin=pkg/compiler/result_bounds_test.go:65 TestSuccessfulResultBoundsRejectDifferentReturns
fn affine(n: Int) Result[Int, Cause]:
    if n < 0: return error(Cause("negative {n}"))
    return ok(n + 1)
