// conform: tags=diagnostics
// conform: phase=check
fn affine(n Int) Result[Int, Cause]:
    if n < 0: return error(Cause(f"negative {n}"))
    return ok(n + 1)
