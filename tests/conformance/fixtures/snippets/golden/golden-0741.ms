// conform: tags=diagnostics
// conform: phase=check
fn affine(n: Int) Result[Int, Cause]:
    if n < 0: return ok(9223372036854775807)
    return ok(n + 1)
