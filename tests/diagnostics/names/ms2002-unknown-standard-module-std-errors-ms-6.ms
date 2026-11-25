// conform: tags=diagnostics
// conform: phase=check
import TextError from "@std/errors.ms"

export fn load(n Int) Result[Int, TextError] {
	return ok(n)
}
// expect-error: MS2002 3:8-3:17 unknown standard module @std/errors.ms
// expect-error: MS2001 5:35 unknown type TextError; declare it with 'type TextError:' / 'enum TextError:' / 'interface TextError:', declare it as a type parameter, or import it
