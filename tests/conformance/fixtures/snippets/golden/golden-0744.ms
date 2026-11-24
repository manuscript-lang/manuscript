// conform: tags=diagnostics
// conform: phase=check
fn affine(n Int) Result[Int, Cause]:
    if n < 0:
        return error(Cause(match n:
            value:
                return ok(9223372036854775807)
            null: "negative"
        ))
    return ok(n + 1)
