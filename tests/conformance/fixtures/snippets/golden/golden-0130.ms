// conform: tags=diagnostics
// conform: phase=check
fn f(x: Int?) Int:
    y := match x:
        n: n
        null: 0
    return n
