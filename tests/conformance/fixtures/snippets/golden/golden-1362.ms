// conform: tags=diagnostics
// conform: phase=check
fn consume(value Result[Int, Error]) Void: void
fn caller() Void:
    consume(operation())
