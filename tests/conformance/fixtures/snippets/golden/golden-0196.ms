// conform: tags=diagnostics
// conform: phase=check
type Failure:
    code: Int
impl Error for Failure:
    fn message() String: "failure"
fn failing() Result[Int, Failure]: error(Failure(code: 1))
fn count[T](r: Result[T, Error]) Int: 1
fn use() Int: count(r: failing())
