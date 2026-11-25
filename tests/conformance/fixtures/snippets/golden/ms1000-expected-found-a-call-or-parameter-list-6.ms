// conform: tags=diagnostics
// conform: phase=check
fn area%d(s: Shape%d) Int {
    var out = 0
    match s {
    }
}
// expect-error: MS1000 3:8-3:9 expected '(', found '%'; a call or parameter list starts with '('
