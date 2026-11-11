// conform: tags=diagnostics
// conform: phase=check
fn callback[T](r: Result[fn(T) Int, Error]) Unit: return
fn first(r: Result[fn(Int) Int, E1]) Unit: callback(r)