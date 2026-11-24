// conform: tags=diagnostics
// conform: phase=check
fn operation() Result[Void, Error] => ok()
fn f() Result[Int, Error]:
    operation()?
    return ok(1)
