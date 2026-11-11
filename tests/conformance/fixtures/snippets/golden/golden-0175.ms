// conform: tags=diagnostics
// conform: phase=check
type Cause[T]:
    detail: T
impl Error for Cause[T]:
    fn message() String: self.detail.to_string()
fn identity[T](value: T) T: value
fn consume[T](value: T, cause: Error, optional: T?) Unit: return
fn first() Unit: consume(value: 1, cause: identity(Cause(2)), optional: identity(3))
