// conform: tags=diagnostics
// conform: phase=check
import TextError from "@std/errors.ms"
fn fail() Result[Int, TextError]:
    return error(TextError("boom"))
fn use() Unit:
    fail()
