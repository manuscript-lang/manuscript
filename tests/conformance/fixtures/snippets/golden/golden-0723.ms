// conform: tags=diagnostics
// conform: phase=check
fn both[T, E: Error](cause: E, r: Result[T, E]) Unit: return
fn first(cause: Error) Unit: both(cause: cause, r: f())