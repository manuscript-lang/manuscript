// conform: tags=diagnostics
// conform: phase=check
fn operation() Result[Void, Error] => ok()
test "valid":
    operation()?
