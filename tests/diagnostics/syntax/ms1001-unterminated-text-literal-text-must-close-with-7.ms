// conform: tags=diagnostics
// conform: phase=check
.ms"
fn example() Void {
}
// expect-error: MS1001 3:4 unterminated text literal; text must close with '"' on the same line, so add the quote or write \\n for a line break
// expect-error: MS1000 5:1-5:2 a block cannot be empty; add at least one statement, or write '...' inside the braces for a runtime-bound declaration
