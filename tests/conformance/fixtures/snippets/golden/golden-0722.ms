// conform: tags=diagnostics
// conform: phase=check
fn bounded[T Equal](r Result[T, Error]) Void: return
fn first() Void: bounded(f())