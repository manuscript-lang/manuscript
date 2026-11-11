// conform: tags=diagnostics
// conform: phase=check
fn f() Unit:
    if true: use() else if false: use()
