// conform: tags=diagnostics
// conform: phase=check
fn f() Int:
    var x: Int = 1
    x += try 3
    return x
