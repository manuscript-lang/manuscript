// conform: tags=diagnostics
// conform: phase=check
fn bounded[T: Equal](r: Result[T, Error]) Unit: return
fn first() Unit: bounded(f())