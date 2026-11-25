// conform: tags=diagnostics
// conform: phase=check
fn broken() String => return "unterminated
// expect-error: MS1001 3:30 unterminated text literal; text must close with '"' on the same line, so add the quote or write \\n for a line break
