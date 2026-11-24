// conform: tags=diagnostics
// conform: phase=check
fn callback[T](r Result[fn(T) Int, Error]) Void => return
fn first(r Result[fn(Int) Int, E1]) Void => callback(r)