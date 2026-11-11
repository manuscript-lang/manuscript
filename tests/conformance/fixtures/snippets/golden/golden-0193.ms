// conform: tags=diagnostics
// conform: phase=check
type Failure:
    detail: String
impl Error for Failure:
    fn message() String: self.detail
fn fail_cause[T, E: Error](cause: E) Result[T, E]: error(cause)
fn first() Result[Int, Error]: fail_cause(Failure("empty"))
