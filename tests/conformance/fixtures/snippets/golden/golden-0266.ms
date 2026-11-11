// conform: tags=diagnostics
// conform: phase=check
enum S:
    A
    B
    C
fn f(s: S) Int:
    match s:
        A:
            return 1
    return 0
