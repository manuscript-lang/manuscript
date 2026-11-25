// conform: tags=diagnostics
// conform: phase=check
"
fn check() Int {
    return read(value: Value(value: 3))
}
// expect-error: MS1001 3:1 unterminated text literal; text must close with '"' on the same line, so add the quote or write \\n for a line break
