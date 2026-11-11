// conform: tags=diagnostics
// conform: phase=check
fn twice[T](r: Result[T, Error]??) Unit: return
fn first() Unit: twice(f())