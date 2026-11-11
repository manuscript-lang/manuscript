// conform: tags=diagnostics
// conform: phase=check
import TextError from "@std/errors.ms"
export fn load(n: Int) Result[Int, TextError]:
    return ok(n)
