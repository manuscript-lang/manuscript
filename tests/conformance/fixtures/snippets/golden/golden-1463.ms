// conform: tags=diagnostics
// conform: phase=check
import TextError from "@std/errors.ms"
fn deep(value: Result[Int, TextError]) Int:
    return value.get()
export fn main() Int:
    return deep(error(TextError("expected failure")))
