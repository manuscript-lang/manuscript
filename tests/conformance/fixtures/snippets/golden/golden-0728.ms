// conform: tags=diagnostics
// conform: phase=check
fn bounded[T: Equal](r: Result[T, Error]) Unit: return
fn first(r: Result[Error, E1]) Unit: bounded(r)