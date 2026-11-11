// conform: tags=diagnostics
// conform: phase=check
fn recurse[T](value: T, count: Int) T:
    if count == 0:
        return value
    return recurse(value: value, count: count - 1)
