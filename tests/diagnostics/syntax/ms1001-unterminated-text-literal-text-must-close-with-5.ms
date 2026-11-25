// conform: tags=diagnostics
// conform: phase=check
fn f() Int {
    s := "abc
    return 1
}
// expect-error: MS1001 4:10 unterminated text literal; text must close with '"' on the same line, so add the quote or write \\n for a line break
