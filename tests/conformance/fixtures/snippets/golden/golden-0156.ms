// conform: tags=diagnostics
// conform: phase=check
fn wrong(cause: Error) String:
    match cause:
        JsonError(first):
            return first.message()
        JsonError(second):
            return second.message()
        _:
            return cause.message()
