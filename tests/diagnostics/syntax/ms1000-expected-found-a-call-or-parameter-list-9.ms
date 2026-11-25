// conform: tags=diagnostics
// conform: phase=check
fn later%d(
value: ) Int {
    return 1
}
// expect-error: MS1000 3:9-3:10 expected '(', found '%'; a call or parameter list starts with '('
