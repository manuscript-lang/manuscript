// conform: tags=diagnostics
// conform: phase=check
fn value() String {
    return "
}
// expect-error: MS1001 4:12 unterminated text literal; text must close with '"' on the same line, so add the quote or write \\n for a line break
