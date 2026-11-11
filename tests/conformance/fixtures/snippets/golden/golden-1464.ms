// conform: tags=diagnostics
// conform: phase=check
import TextError from "@std/errors.ms"
export fn main() Int:
    value: Result[Int, TextError] := ok(0)
    extract := value.err
    return extract().text.scalar_length()
