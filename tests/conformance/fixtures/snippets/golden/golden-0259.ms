// conform: tags=diagnostics
// conform: phase=check
fn id[T](x: T) T:
    return x
fn f() Int:
    g := id
    return g(1)
