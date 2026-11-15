// conform: tags=diagnostics
// conform: phase=check
fn operation() Result[Void, Int]: ok(void)
fn f() Result[Int, Error]:
    operation()?
    return ok(1)
