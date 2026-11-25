// conform: tags=diagnostics
// conform: phase=check
fn step%d[T](value: T) T: return step%d(value)
// expect-error: MS1000 3:8-3:9 expected '(', found '%'; a call or parameter list starts with '('
