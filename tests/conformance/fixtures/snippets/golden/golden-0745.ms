// conform: tags=diagnostics
// conform: phase=check
fn affine(n: Int) Result[Int, Cause]:
    if n < 0: return error(Cause("negative"))
    return ok(n + 9223372036854775807)
