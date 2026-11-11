// conform: tags=diagnostics
// conform: phase=check
fn domain[T](r: Result[T, E2]) Unit: return
fn first() Unit: domain(f())