// conform: tags=diagnostics
// conform: phase=check
fn operation() Result[Unit, Error]: ok(unit)
fn f() Result[Int, Error]:
    operation()?
    return ok(1)
