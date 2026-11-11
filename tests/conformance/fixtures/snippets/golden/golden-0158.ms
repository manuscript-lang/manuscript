// conform: tags=diagnostics
// conform: phase=check
type Box[T]:
    item: T
impl Error for Box[T]:
    fn message() String:
        return "box"
fn wrong(cause: Error) String:
    match cause:
        Box(value):
            return value.message()
        _:
            return cause.message()
