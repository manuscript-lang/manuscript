// conform: tags=diagnostics
// conform: phase=check
fn use(value: Int?) Int:
    return match value:
        _value:
            callback := fn(n: Int = match value:
                x: x
                none: 0
            ) Int:
                return n
            callback()
        none: 0
