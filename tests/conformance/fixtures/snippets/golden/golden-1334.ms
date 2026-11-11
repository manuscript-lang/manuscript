// conform: tags=diagnostics
// conform: phase=check
enum Failure:
    NotFound
    Denied(reason: String)
impl Error for Failure:
    fn message() String: "f"
fn classify(result: Result[Int, Failure]) Int:
    match result:
        error(NotFound): return 1
        ok(value): return value
