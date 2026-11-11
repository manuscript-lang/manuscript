// conform: tags=diagnostics
// conform: phase=check
interface Starter:
    fn start(operation: fn() Unit) Unit
type Sequential: ...
impl Starter for Sequential:
    fn start(operation: fn() Unit) Unit:
        operation()
fn run() Unit:
    values := [0]
    Sequential().start(fn:
        values.append(1)
    )
