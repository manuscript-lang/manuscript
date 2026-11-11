// conform: tags=diagnostics
// conform: phase=check
type Box[T]:
    value: T
fn hash(box: Box[Box[Int]]) Int: return box.hash()
