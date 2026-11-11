// conform: tags=diagnostics
// conform: phase=check
type Holder[T]:
    r: Result[T, Error]
fn first() Holder[Int]: Holder(f())