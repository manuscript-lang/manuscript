// conform: tags=diagnostics
// conform: phase=check
import arguments from "@std/os/process.ms"
import stdout, stderr from "@std/io/io.ms"
export fn main() Int:
    args := arguments()
    _out := stdout().write(data: "out={args[0]}\n")
    _err := stderr().write(data: "stderr\n")
    return 7
