// conform: tags=diagnostics
// conform: phase=check
fn use(value: Int) Unit:
    return
test "continued argument":
    use(value:
        3
    )
