// conform: tags=diagnostics
// conform: phase=check
fn wrong(cause: Error) String:
    match cause:
        JsonError.InvalidData(value):
            return "invalid"
        _:
            return cause.message()
