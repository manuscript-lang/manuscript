// conform: tags=diagnostics
// conform: phase=check
fn affine%d(value: Int) Result[Int, TextError]:
    if value < 0: return error(TextError("negative"))
    return ok(value + 1)
