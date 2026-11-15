// conform: tags=diagnostics
// conform: phase=check
fn consume(value: Result[Int, Error]) Void: unit
fn caller() Void:
    consume(operation())
