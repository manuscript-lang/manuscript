// conform: tags=diagnostics
// conform: phase=check
fn f[T](value: T, copy: T = value) T:
    return copy
fn call() Int:
    return f()
