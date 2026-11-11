// conform: tags=diagnostics
// conform: phase=check
type Box[T]:
    value: T
fn f() Box[Int]:
    return Box(value: 1)
