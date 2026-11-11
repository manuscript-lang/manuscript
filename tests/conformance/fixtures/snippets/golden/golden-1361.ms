// conform: tags=diagnostics
// conform: phase=check
fn caller() Result[Int, Error]:
    value := operation()
    return value
