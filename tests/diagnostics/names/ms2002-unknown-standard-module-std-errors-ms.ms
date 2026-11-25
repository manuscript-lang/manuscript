// conform: tags=diagnostics
// conform: phase=check
import TextError from "@std/errors.ms"

fn fail() Result[Int, TextError] {
	return error(TextError("boom"))
}

fn use() Void {
	fail()
}
// expect-error: MS2002 3:8-3:17 unknown standard module @std/errors.ms
// expect-error: MS2001 5:23 unknown type TextError; declare it with 'type TextError:' / 'enum TextError:' / 'interface TextError:', declare it as a type parameter, or import it
// expect-error: MS2001 6:18 unknown binding TextError; declare it with 'TextError := ...' before use, define 'fn TextError(...) T { ... }', or import it from a module
