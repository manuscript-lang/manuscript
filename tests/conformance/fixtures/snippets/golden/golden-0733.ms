// conform: tags=diagnostics
// conform: phase=check
fn nested[T](r: Result[Result[T, Error], Error]) Unit: return
fn first(r: Result[Result[Int, E1], E2]) Unit: nested(r)