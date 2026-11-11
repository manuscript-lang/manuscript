// conform: tags=diagnostics
// conform: phase=check
fn consume(value: Result[Int, Error]) Unit: unit
fn caller() Unit:
    consume(operation())
