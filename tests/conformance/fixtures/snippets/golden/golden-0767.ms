// conform: tags=diagnostics
// conform: phase=check
fn operation() Result[Void, Error]: ok(unit)
test "valid":
    operation()?
