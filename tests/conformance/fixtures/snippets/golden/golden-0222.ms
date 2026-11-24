// conform: tags=diagnostics
// conform: phase=check
fn peek() Missing:
    return 0
fn f() Int:
    match peek():
        x:
            return x
        null:
            return 0
