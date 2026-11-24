// conform: tags=diagnostics
// conform: phase=check
fn f() Void:
    g := fn(x Int) Result[Int, String]: ok(x)
    return
