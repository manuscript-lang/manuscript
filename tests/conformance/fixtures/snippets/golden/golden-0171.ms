// conform: tags=diagnostics
// conform: phase=check
import nanoseconds, sleep from "@std/time.ms"
import stdout from "@std/io/io.ms"
fn main() Unit:
    stdout().write(data: "ready\n")
    sleep(nanoseconds(60000000000))
