// conform: tags=diagnostics
// conform: phase=check
fn g[T](x: T) Int:
    return 0
fn f() Int:
    return g()
