// conform: tags=diagnostics
// conform: phase=check
fn f() Unit:
    consume(transform: fn() Unit:
        return
        )
