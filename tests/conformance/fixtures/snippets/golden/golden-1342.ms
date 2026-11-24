// conform: tags=diagnostics
// conform: phase=check
type Box[T]:
    value T
fn use[T](value Box[T]?) T:
    match value:
        box => return Box.value
        null => return panic(message: "empty")
