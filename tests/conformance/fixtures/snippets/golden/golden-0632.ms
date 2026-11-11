// conform: tags=diagnostics
// conform: phase=check
fn f[T](value: T?) T: return value.get()
fn call() Unit: value := f(none)
