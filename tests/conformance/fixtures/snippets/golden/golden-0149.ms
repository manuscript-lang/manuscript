// conform: tags=diagnostics
// conform: phase=check
fn wrong(operation: fn() JsonError) fn() Error:
    return operation
