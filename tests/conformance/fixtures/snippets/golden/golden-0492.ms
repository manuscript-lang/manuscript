// conform: tags=diagnostics
// conform: phase=check
enum Optional[T]:
    T
    null
fn wrong(value: Int?) Result[Int, String]: value.ok_or("missing")