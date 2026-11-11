// conform: tags=diagnostics
// conform: phase=check
fn f() Int:
    for mode in [1]:
        if not (
                mode == 2
            ):
                return 2
    return 3
