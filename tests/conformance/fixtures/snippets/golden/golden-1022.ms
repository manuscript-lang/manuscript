// conform: tags=diagnostics
// conform: phase=check
interface Starter:
    fn start(operation fn() Void) Void
type Sequential: ...
impl Starter for Sequential:
    fn start(operation: fn() Void) Void:
        operation()
fn run() Void:
    values := [0]
    Sequential().start(fn:
        values.append(1)
    )
