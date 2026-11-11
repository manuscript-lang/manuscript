// conform: tags=diagnostics
// conform: phase=check
impl Error for Result:
    fn message() String:
        return "x"
fn general(value: Result) Error:
    return value
