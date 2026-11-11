// conform: tags=diagnostics
// conform: phase=check
fn use(value: Result[Int, Error]) Int:
    match value:
        ok(n): return n
        error(_): return 0
