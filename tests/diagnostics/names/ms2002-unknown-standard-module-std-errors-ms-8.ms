// conform: tags=diagnostics
// conform: phase=check
import TextError from "@std/errors.ms"

fn checked(n Int) Result[Int, TextError] {
	if n < 0 {
		return error(TextError("negative"))
	}
	return ok(n + 1)
}

fn chain(n Int) Result[Int, TextError] {
	value := checked(n)?
	return ok(value)
}

export fn main() Int {
	return chain(9223372036854775807).get()
}
// expect-error: MS2002 3:8-3:17 unknown standard module @std/errors.ms
// expect-error: MS2001 5:31 unknown type TextError; declare it with 'type TextError:' / 'enum TextError:' / 'interface TextError:', declare it as a type parameter, or import it
// expect-error: MS2001 12:29 unknown type TextError; declare it with 'type TextError:' / 'enum TextError:' / 'interface TextError:', declare it as a type parameter, or import it
// expect-error: MS2001 7:22 unknown binding TextError; declare it with 'TextError := ...' before use, define 'fn TextError(...) T { ... }', or import it from a module
