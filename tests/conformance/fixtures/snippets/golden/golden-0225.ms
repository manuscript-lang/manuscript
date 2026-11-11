// conform: tags=diagnostics
// conform: phase=check
impl Error for Result[Int]:
    fn message() String:
        return "x"
fn f(x: Result[Int]) Result[Int, Error]:
    return error(x)
