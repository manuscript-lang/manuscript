// conform: tags=diagnostics
// conform: phase=check
import TextError from "@std/errors.ms"

fn crash() TextError {
	return TextError((1 / 0).to_string())
}

fn main() Void {
	value Int? := null
	result := value.ok_or_else(crash)
}
// expect-error: MS2002 3:8-3:17 unknown standard module @std/errors.ms
// expect-error: MS2001 5:12 unknown type TextError; declare it with 'type TextError:' / 'enum TextError:' / 'interface TextError:', declare it as a type parameter, or import it
// expect-error: MS2001 6:12 unknown binding TextError; declare it with 'TextError := ...' before use, define 'fn TextError(...) T { ... }', or import it from a module
// expect-error: MS3000 11:21 a nullable has no method `ok_or_else`; write `if x != null { ... }` and use `x`
