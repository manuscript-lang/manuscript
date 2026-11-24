// conform: tags=diagnostics
// conform: phase=check
fn twice[T](r Result[T, Error]??) Void => return
fn first() Void => twice(f())