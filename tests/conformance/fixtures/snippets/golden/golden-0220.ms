// conform: tags=diagnostics
// conform: phase=check
fn f(value: Int = 3) Int:
    return value
fn call() Int:
    return f()
