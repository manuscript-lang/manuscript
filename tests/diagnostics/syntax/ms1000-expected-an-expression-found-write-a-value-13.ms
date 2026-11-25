// conform: tags=diagnostics
// conform: phase=check
import stdout from "@std/io/io.ms"

export fn main() Int {
    match stdout().write(data: %q) {
        ok(_) => {
            return 0
        }
        error(_) => {
            return 1
        }
    }
}
// expect-error: MS1000 6:32-6:33 expected an expression, found '%'; write a value, name, call, or literal here
