// conform: tags=diagnostics
// conform: phase=check
fn f(value: Int) Int: return value
fn call() Unit:
    callback: fn(Int?) Int := f
