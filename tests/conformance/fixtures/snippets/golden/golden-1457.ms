// conform: tags=diagnostics
// conform: phase=check
import TextError from "@std/errors.ms"
fn checked(n: Int) Result[Int, TextError]:
    if n < 0:
        return error(TextError("negative"))
    return ok(n + 1)
fn chain(n: Int) Result[Int, TextError]:
    value := checked(n)?
    return ok(value)
export fn main() Int:
    return chain(9223372036854775807).get()
