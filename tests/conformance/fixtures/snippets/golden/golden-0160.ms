// conform: tags=diagnostics
// conform: phase=check
fn diagnostic(cause: %s) String:
    return cause.message()
fn view(cause: %s) Error:
    return cause
