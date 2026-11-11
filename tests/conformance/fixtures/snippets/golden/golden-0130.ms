// conform: tags=diagnostics
// conform: phase=check
fn f(x: Int?) Int:
    y := match x:
        n: n
        none: 0
    return n
