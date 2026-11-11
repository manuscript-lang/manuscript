// conform: tags=diagnostics
// conform: phase=check
type Other:
    detail: String
fn wrong(cause: Error) String:
    match cause:
        Other(value):
            return value.detail
        _:
            return cause.message()
