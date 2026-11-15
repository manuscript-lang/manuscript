// conform: tags=diagnostics
// conform: phase=check
fn operation() Result[Void, Error]: ok(void)
fn caller() Result[Int, Error]:
    operation()?
    return ok(1)
