// conform: tags=diagnostics
// conform: phase=check
fn helper() Int:
    return 1
fn f() Int:
    helper = 2
    return 0
