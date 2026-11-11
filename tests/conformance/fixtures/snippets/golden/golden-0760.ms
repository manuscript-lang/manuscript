// conform: tags=diagnostics
// conform: phase=check
import TextError from "@std/errors.ms"
fn tail(value: Result[Int, TextError]) Result[Int, Error]:
    output := try value
    return ok(output)
