// conform: tags=diagnostics
// conform: phase=check
import stderr from "@std/io/io.ms"

fn main() Void {
    stream := stderr()
    chunk := "
}
// expect-error: MS1001 7:14 unterminated text literal; text must close with '"' on the same line, so add the quote or write \\n for a line break
