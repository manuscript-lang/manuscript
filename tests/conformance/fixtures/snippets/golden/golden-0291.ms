// conform: tags=diagnostics
// conform: phase=check
fn double(n: Int) Int:
    return n * 2
fn f() Int:
    return [1, 2].map(double).length()
