// conform: tags=diagnostics
// conform: phase=check
fn use(value Int) Void:
    return
test "continued argument":
    use(value:
        3
    )
