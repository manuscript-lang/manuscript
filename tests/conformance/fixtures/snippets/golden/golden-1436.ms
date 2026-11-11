// conform: tags=diagnostics
// conform: phase=check
import stderr from "@std/io/io.ms"

fn main() Unit:
    stream := stderr()
    chunk := "