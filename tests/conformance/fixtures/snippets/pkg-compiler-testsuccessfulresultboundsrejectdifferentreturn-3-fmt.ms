# conform: tags=control-flow,formatter,interpolation,parser,tier-core,try-result
# conform: phase=parse
# conform: origin=pkg/compiler/result_bounds_test.go:65 TestSuccessfulResultBoundsRejectDifferentReturns
def affine(n: Int) -> Result[Int, Cause]:
    if n < 0: return error(Cause(f"negative {n}"))

    return ok(n + 1)
