// conform: tags=diagnostics
// conform: phase=check
fn convert[T, U](value: T) U?: none
fn first() Unit:
    value := convert(1)
