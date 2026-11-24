// conform: tags=diagnostics
// conform: phase=check
fn operation() Result[Void, Error] => ok()
fn f() Void:
    operation()?
