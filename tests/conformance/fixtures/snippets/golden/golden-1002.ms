// conform: tags=diagnostics
// conform: phase=check
fn f() Unit:
    g := fn(x: Int) Result[Int, String]: ok(x)
    return unit
