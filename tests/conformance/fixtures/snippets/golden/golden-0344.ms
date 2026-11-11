// conform: tags=diagnostics
// conform: phase=check
type Box[T]:
    value: T
type Nested:
    value: Box[Box[Int]]
