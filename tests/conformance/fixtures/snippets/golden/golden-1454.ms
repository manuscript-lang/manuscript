// conform: tags=diagnostics
// conform: phase=check
fn copy[T](value: T) T: return value
export type Box[T]:
    value: T
    copied: T = copy(value)
    items: List[T] = [value]
