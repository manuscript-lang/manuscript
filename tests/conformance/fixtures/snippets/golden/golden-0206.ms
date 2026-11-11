// conform: tags=diagnostics
// conform: phase=check
fn f(first: Int = 1, second: Int) Int:
    return first + second
fn call() Int:
    return f()
