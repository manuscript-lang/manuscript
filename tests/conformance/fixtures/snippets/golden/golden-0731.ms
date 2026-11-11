// conform: tags=diagnostics
// conform: phase=check
fn values[T](r: List[Result[T, Error]]) Unit: return
fn first() Unit: values([f()])