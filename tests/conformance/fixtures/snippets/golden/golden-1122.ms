// conform: tags=diagnostics
// conform: phase=check
fn run(n: Int) Int:
    a := n | .size() | try .m() | .k
    return a
