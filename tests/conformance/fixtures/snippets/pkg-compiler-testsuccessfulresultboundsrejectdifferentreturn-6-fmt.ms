# conform: tags=control-flow,formatter,parser,tier-core,try-result
# conform: phase=parse
# conform: origin=pkg/compiler/result_bounds_test.go:82 TestSuccessfulResultBoundsRejectDifferentReturns
fn affine(n: Int) Int!Cause:
    if n < 0: return error(Cause("negative"))

    return ok(n + 9223372036854775807)
