// conform: tags=diagnostics
// conform: phase=check
fn absent[T]() T?: none
fn transform[T, U](callback: fn(T) U) fn(T) U: callback
fn answer() Unit:
    empty: Int? := absent()
    callback: fn(Int) String := transform(fn item: item.to_string())
