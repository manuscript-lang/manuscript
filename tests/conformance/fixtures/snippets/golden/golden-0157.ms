// conform: tags=diagnostics
// conform: phase=check
fn wrong(cause: Error) String:
    match cause:
        _:
            return cause.message()
        JsonError(value):
            return value.message()
