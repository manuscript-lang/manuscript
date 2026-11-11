// conform: tags=diagnostics
// conform: phase=check
fn operation() Result[Unit, Error]: ok(unit)
test "valid":
    operation()?
