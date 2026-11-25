// conform: tags=diagnostics
// conform: phase=check
export fn f_%d_%d(value: Int) Int: value + %d
// expect-error: MS1000 3:13-3:14 expected '(', found '%'; a call or parameter list starts with '('
