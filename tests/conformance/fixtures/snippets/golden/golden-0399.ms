// conform: tags=diagnostics
// conform: phase=check
fn f(n: Int) Int: n
fn apply(callback: fn(Int) Int, input: Int) Int: callback(input)