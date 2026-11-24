// conform: tags=diagnostics
// conform: phase=check
fn bounded[T Equal](r Result[T, Error]) Void => return
fn first(r Result[Error, E1]) Void => bounded(r)