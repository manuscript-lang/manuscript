// conform: tags=diagnostics
// conform: phase=check
fn f(value: Int = 1) Int:
    return value
fn call() Int:
    return f(other: 3)
