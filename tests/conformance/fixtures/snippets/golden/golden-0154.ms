// conform: tags=diagnostics
// conform: phase=check
fn wrong(cause: Error) String:
    match cause:
        JsonError:
            return "invalid"
        _:
            return cause.message()
