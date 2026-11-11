// conform: tags=diagnostics
// conform: phase=check
type Cause:
    text: String
impl Error for Cause:
    fn message() String: self.text
fn affine(n: Int) Result[Int, Cause]:
    if n < 0:
        return error(Cause("negative"))
    return ok(n + 1)
fn wrapped(n: Int) Result[Int, Cause]:
    value := affine(n)?
    return ok(value)
fn twice(n: Int) Result[Int, Cause]:
    value := wrapped(n)?
    return ok(value)
