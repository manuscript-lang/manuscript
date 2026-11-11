// conform: tags=diagnostics
// conform: phase=check
fn f(a: Int, b: Int) Int:
    return a + b
fn call() Int:
    return f(1, 2)
