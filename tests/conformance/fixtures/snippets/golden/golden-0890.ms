// conform: tags=diagnostics
// conform: phase=check
fn f() Int:
    if true && false:
        return 1
    return 0
