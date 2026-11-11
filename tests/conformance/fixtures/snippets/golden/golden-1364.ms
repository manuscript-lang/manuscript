// conform: tags=diagnostics
// conform: phase=check
fn caller() Result[Int, Error]:
    return match operation():
        ok(value):
            operation()
            operation()
        error(cause): operation()
