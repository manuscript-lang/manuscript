// conform: tags=diagnostics
// conform: phase=check
import TextError from "@std/errors.ms"
fn fail[T](message: String) Result[T, TextError]: error(TextError(message))
fn first() Result[Int, TextError]: fail[Int]("empty")
