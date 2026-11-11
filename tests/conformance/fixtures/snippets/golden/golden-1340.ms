// conform: tags=diagnostics
// conform: phase=check
enum Failure[T]:
    NotFound
    Denied(reason: T)
impl Error for Failure[T]:
    fn message() String: "f"
fn use[T](value: Result[Int, Failure[T]]) Int:
    match value:
        error(NotFound): return 1
        ok(value): return value
