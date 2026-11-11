// conform: tags=diagnostics
// conform: phase=check
fn wrap[T](callback: (fn(Int) T)?) Unit: return
fn apply[T, U](value: T, transform: fn(T) U) U: transform(value)
fn first() Unit:
    offset := 7
    result := apply(value: 1, transform: fn outer: apply(value: 2, transform: fn inner: outer + inner + offset))
    wrap(fn(item: Int = 4): item + offset)
