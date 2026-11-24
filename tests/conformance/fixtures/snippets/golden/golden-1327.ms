// conform: tags=diagnostics
// conform: phase=check
fn inner(value Int?) Int:
    return match value:
        n: n
        null: 0
fn use(value Int?) Int:
    return match value:
        _value: inner(value)
        null: 0
