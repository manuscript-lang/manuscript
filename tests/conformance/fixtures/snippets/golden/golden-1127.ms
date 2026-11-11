// conform: tags=diagnostics
// conform: phase=check
fn f() Int:
    if a:
        return 1
    else if foo(
            a
        ):
            return 2
    return 3
