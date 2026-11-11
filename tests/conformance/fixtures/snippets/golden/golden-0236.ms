// conform: tags=diagnostics
// conform: phase=check
type Int:
    x: Int
fn f() Int:
    t := Int(x: 2)
    return 0
