// conform: tags=diagnostics
// conform: phase=check
import stdout from "@std/io/io.ms"

fn main() Void! {
    return stdout().write(data: %q)
}
// expect-error: MS1000 6:33-6:34 expected an expression, found '%'; write a value, name, call, or literal here
