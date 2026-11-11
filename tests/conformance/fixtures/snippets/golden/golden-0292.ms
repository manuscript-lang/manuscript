// conform: tags=diagnostics
// conform: phase=check
fn positive(n: Int) Bool:
    return n > 0
fn f() Int:
    return [1].filter(positive).length()
