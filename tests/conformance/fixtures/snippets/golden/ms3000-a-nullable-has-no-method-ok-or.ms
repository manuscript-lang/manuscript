// conform: tags=diagnostics
// conform: phase=check
fn cause(value Int) String => "cause"

fn wrong(value Int?) Result[Int, String] => value.ok_or_else(cause)
// expect-error: MS3000 5:51 a nullable has no method `ok_or_else`; write `if x != null { ... }` and use `x`
