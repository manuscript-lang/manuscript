// conform: tags=diagnostics
// conform: phase=check
import TextError from "@std/errors.ms"
fn crash(cause: TextError) Int:
    return 1 / 0
export fn main() Int:
    value: Result[Int, TextError] := error(TextError("expected failure"))
    return value.or_else(crash)
