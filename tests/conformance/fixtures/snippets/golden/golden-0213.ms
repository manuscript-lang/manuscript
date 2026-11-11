// conform: tags=diagnostics
// conform: phase=check
fn f(value: Int = 1) Int:
    return value
fn apply(callback: fn(Int) Int) Int:
    return callback()
