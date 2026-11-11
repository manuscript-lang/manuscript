// conform: tags=diagnostics
// conform: phase=check
fn use(value: Result[Int, Error]) Int:
    return match value:
        ok(n): n
        error(_): 0
