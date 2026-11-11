// conform: tags=diagnostics
// conform: phase=check
type Growing[T]:
    value: T
    next: Int = grow([value])
fn grow[T](value: T) Int:
    item := Growing(value: value)
    return 0
