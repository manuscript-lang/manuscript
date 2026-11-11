// conform: tags=diagnostics
// conform: phase=check
import TextError from "@std/errors.ms"
fn crash(value: Int) Int:
    return 1 / value
export fn main() Int:
    value: Result[Int, TextError] := ok(0)
    return value.map(crash).get()
