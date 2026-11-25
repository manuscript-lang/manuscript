// conform: tags=diagnostics
// conform: phase=check
import TextError from "@std/errors.ms"

export fn main() Int {
	value Result[Int, TextError] := ok(0)
	extract := value.err
	return extract().text.scalar_length()
}
// expect-error: MS2002 3:8-3:17 unknown standard module @std/errors.ms
// expect-error: MS2001 6:23 unknown type TextError; declare it with 'type TextError:' / 'enum TextError:' / 'interface TextError:', declare it as a type parameter, or import it
