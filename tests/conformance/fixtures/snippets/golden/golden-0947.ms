// conform: tags=diagnostics
// conform: phase=check
fn f() Unit:
    use(fn(value, other: Int):
        return value + other
    )
