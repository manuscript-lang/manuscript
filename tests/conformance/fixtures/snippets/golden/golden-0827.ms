// conform: tags=diagnostics
// conform: phase=check
fn work%d(value: Int) Int: return value + %d
// expect-error: MS1000 3:8-3:9 expected '(', found '%'; a call or parameter list starts with '('
