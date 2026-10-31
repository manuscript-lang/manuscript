# conform: tags=control-flow,formatter,interpolation,parser,tier-core,try-result
# conform: phase=parse
# conform: origin=pkg/compiler/result_bounds_test.go:65 TestSuccessfulResultBoundsRejectDifferentReturns
fn affine(n: Int) Int!Cause:
    if n < 0: return error(Cause("negative {n}"))

    return ok(n + 1)
