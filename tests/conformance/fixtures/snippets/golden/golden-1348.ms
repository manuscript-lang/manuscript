// conform: tags=diagnostics
// conform: phase=check
enum Failure:
    NotFound
    Denied(reason: String)
impl Error for Failure:
    fn message() String: "f"
fn failure_code(cause: Failure) Int:
    match cause:
        NotFound: return 1
        Denied(_): return 2
fn classify(result: Result[Int, Failure]) Int:
    match result:
        error(cause): return failure_code(cause)
        ok(value): return value
