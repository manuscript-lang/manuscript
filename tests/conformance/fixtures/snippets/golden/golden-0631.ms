// conform: tags=diagnostics
// conform: phase=check
fn f[T](value T? = null) Void => return
fn call() Void => f()
