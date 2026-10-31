# conform: tags=control-flow,formatter,match,optional,parser,tier-core,try-result
# conform: phase=parse
# conform: origin=pkg/compiler/result_bounds_test.go:73 TestSuccessfulResultBoundsRejectDifferentReturns
fn affine(n: Int) Result[Int, Cause]:
    if n < 0:
        return error(
            Cause(
                match n:
                    value:
                        return ok(9223372036854775807)
                    none: "negative"
            )
        )

    return ok(n + 1)
