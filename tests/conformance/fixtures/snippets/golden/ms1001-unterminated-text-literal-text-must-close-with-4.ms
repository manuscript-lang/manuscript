// conform: tags=diagnostics
// conform: phase=check
.ms"
fn check() Void {
    decoded := parse(text: "a: 1")
}
// expect-error: MS1001 3:4 unterminated text literal; text must close with '"' on the same line, so add the quote or write \\n for a line break
