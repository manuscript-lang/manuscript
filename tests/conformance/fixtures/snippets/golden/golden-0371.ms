// conform: tags=diagnostics
// conform: phase=check
fn g(v: Int) Int:
    return v
fn f() Int:
    x := 1
    return g(v: x.foo())
