# conform: tags=control-flow,formatter,parser,tier-core,try-result
# conform: phase=parse
# conform: origin=pkg/compiler/result_bounds_test.go:69 TestSuccessfulResultBoundsRejectDifferentReturns
fn affine(n: Int) Result[Int, Cause]:
    if n < 0: return error(Cause())

    return ok(n + 1)
