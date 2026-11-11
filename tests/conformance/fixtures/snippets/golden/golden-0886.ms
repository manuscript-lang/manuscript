// conform: tags=diagnostics
// conform: phase=check
fn g(x: Int) Int:
    return x
fn f() Int:
    return g(x = 1)
