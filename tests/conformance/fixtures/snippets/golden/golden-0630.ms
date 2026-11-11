// conform: tags=diagnostics
// conform: phase=check
fn f[T](first: T?, second: T) Unit: return
fn call() Unit: f(first: 4, second: "wrong")
