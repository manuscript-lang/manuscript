// conform: tags=diagnostics
// conform: phase=check
fn g(a: Int) Int:
    return a
fn f() Int:
    return g()
