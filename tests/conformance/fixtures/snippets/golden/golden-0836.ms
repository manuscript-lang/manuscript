// conform: tags=diagnostics
// conform: phase=check
fn f(r: Result[Int?, String]) Int:
    match r:
        ok(n): return n
    return 0
