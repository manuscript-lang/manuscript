// conform: tags=diagnostics
// conform: phase=check
fn f%d() Int: 1
// expect-error: MS1000 3:5-3:6 expected '(', found '%'; a call or parameter list starts with '('
