// conform: tags=diagnostics
// conform: phase=check
enum A:
    X(n: Int)
enum B:
    X(n: Int)
fn f() Int:
    a := X(n: 1)
    return 1
