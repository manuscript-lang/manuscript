// conform: tags=diagnostics
// conform: phase=check
fn wrong(cause: Error) String:
    match cause:
        JsonError(value):
            return value.message()
