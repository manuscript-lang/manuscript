// conform: tags=diagnostics
// conform: phase=check
fn operation() Unit: unit
fn f() Result[Int, Error]:
    operation()?
    return ok(1)
