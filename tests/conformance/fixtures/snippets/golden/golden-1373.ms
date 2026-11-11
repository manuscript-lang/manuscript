// conform: tags=diagnostics
// conform: phase=check
import stdout from "@std/io/io.ms"

fn say(text: String) Result[Unit, Error]:
    stdout().write("{text}\n")?
    return stdout().flush()

fn add(a: Int, b: Int) Int:
    return a + b

export fn run() Int:
    return add(1, 2)
