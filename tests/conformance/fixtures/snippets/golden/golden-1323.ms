// conform: tags=diagnostics
// conform: phase=check
fn use(value Int?) Int:
    return match value:
        _value:
            callback := fn(n Int = match value:
                x: x
                null: 0
            ) Int:
                return n
            callback()
        null: 0
