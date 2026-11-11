// conform: tags=diagnostics
// conform: phase=check
enum Result[T, E]:
    ok(value: T)
    error(cause: E)
fn wrong(value: Result[Int, String]) Int: value.get()