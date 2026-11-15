// conform: tags=diagnostics
// conform: phase=check
fn convert[T, U](value: T) U?: none
fn first() Void:
    value := convert(1)
