// conform: tags=diagnostics
// conform: phase=check
fn operation() Result[Int, Error]: ok(1)
fn f() Result[Int, Error]:
    operation()?
    return ok(1)
