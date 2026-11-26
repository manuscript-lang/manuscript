// conform: tags=diagnostics
// conform: phase=check
fn f%d[T](value: T) T: f%d(f%d(value))
// expect-error: MS1000 3:5-3:6 expected '(', found '%'; a call or parameter list starts with '('
