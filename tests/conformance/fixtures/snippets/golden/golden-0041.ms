// conform: tags=diagnostics
// conform: phase=check
import arguments from "@std/os/process.ms"
import stdout from "@std/io/io.ms"

fn main() Void!:
    message := f"Arguments: {arguments().length()}\n"
    stdout().write(message)?
