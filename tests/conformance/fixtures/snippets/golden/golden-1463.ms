// conform: tags=diagnostics
// conform: phase=check
import TextError from "@std/errors.ms"

fn deep(value Result[Int, TextError]) Int {
	return value.get()
}

export fn main() Int {
	return deep(error(TextError("expected failure")))
}
// expect-error: MS2002 3:8-3:17 unknown standard module @std/errors.ms
// expect-error: MS2001 5:27 unknown type TextError; declare it with 'type TextError:' / 'enum TextError:' / 'interface TextError:', declare it as a type parameter, or import it
// expect-error: MS2001 10:23 unknown binding TextError; declare it with 'TextError := ...' before use, define 'fn TextError(...) T { ... }', or import it from a module
