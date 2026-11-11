// conform: tags=diagnostics
// conform: phase=check
fn cause(value: Int) String: "cause"
fn wrong(value: Int?) Result[Int, String]: value.ok_or_else(cause)