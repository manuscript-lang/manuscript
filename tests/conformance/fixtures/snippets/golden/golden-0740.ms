// conform: tags=diagnostics
// conform: phase=check
fn affine(n: Int = 0) Result[Int, Cause]:
    if n < 0: return error(Cause("negative"))
    return ok(n + 1)
