// conform: tags=diagnostics
// conform: phase=check
import List from "@std/collections/collections.ms"
fn bad() String => "unterminated
// expect-error: MS1001 4:20 unterminated text literal; text must close with '"' on the same line, so add the quote or write \\n for a line break
