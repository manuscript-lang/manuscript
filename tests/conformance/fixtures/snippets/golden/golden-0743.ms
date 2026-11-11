// conform: tags=diagnostics
// conform: phase=check
fn affine(n: Int) Result[Int, Cause]:
    if n < 0: return error(Cause())
    return ok(n + 1)
