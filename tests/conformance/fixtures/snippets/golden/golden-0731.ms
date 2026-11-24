// conform: tags=diagnostics
// conform: phase=check
fn values[T](r List[Result[T, Error]]) Void: return
fn first() Void: values([f()])