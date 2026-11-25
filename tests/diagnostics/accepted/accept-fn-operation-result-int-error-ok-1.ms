// conform: tags=diagnostics
// conform: phase=check
fn operation() Result[Int, Error] => ok(1)
// expect-exit: 0
