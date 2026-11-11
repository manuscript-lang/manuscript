// conform: tags=diagnostics
// conform: phase=check
fn f(value: Int = 1) Int:
    return value
fn g(value: Int) Int:
    return value
fn call() Int:
    var copy = f
    copy = g
    return copy()
