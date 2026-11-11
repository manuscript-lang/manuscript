// conform: tags=diagnostics
// conform: phase=check
fn f() Int:
    n := [1].map(fn(x) => x + 1)
    return 0
