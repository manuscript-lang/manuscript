// conform: tags=diagnostics
// conform: phase=check
fn operation() Void => void
fn f() Result[Int, Error]:
    operation()?
    return ok(1)
