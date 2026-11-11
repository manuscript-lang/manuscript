// conform: tags=diagnostics
// conform: phase=check
enum Wrapped[T]:
    value(r: Result[T, Error])
fn first() Wrapped[Int]: Wrapped.value(f())