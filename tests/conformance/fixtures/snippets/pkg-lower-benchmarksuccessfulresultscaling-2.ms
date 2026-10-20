# conform: tags=control-flow,parser,tier-core,try-result
# conform: phase=parse
# conform: origin=pkg/lower/int_bounds_test.go:203 BenchmarkSuccessfulResultScaling
fn affine%d(value: Int) Result[Int, TextError]:
    if value < 0: return error(TextError("negative"))
    return ok(value + 1)
