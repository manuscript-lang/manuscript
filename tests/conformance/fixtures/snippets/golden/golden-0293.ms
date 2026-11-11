// conform: tags=diagnostics
// conform: phase=check
enum S:
    A
    B
fn f(s: S) Int:
    match s:
        A:
            return 1
        other:
            return 2
