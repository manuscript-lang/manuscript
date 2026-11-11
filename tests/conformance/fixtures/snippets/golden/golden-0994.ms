// conform: tags=diagnostics
// conform: phase=check
fn f() Int:
    v := x
        | f // first

        // explain
        | g(a: 1)
        .size()
    return 0
