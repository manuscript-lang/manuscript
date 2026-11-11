// conform: tags=diagnostics
// conform: phase=check
fn f(value: Int = 1) Int:
    return value
fn make() fn(Int) Int:
    return f
fn call() Int:
    return make()()
