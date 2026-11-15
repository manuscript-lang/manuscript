// conform: tags=diagnostics
// conform: phase=check
fn operation() Void: unit
fn f() Result[Int, Error]:
    operation()?
    return ok(1)
