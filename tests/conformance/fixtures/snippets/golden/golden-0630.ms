// conform: tags=diagnostics
// conform: phase=check
fn f[T](first: T?, second: T) Void: return
fn call() Void: f(first: 4, second: "wrong")
