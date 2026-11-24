// conform: tags=diagnostics
// conform: phase=check
fn f[T](second T, first T?) Void: return
fn call() Void: f(first: 4, second: "wrong")
