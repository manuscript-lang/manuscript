// conform: tags=diagnostics
// conform: phase=check
import TextError from "@std/errors.ms"

fn crash(cause TextError) Int {
	return 1 / 0
}

export fn main() Int {
	value Result[Int, TextError] := error(TextError("expected failure"))
	return value.or_else(crash)
}
// expect-error: MS2002 3:8-3:17 unknown standard module @std/errors.ms
// expect-error: MS2001 5:16 unknown type TextError; declare it with 'type TextError:' / 'enum TextError:' / 'interface TextError:', declare it as a type parameter, or import it
// expect-error: MS3000 6:14 division by zero always faults; guard the divisor or use a nonzero constant
// expect-error: MS2001 10:23 unknown type TextError; declare it with 'type TextError:' / 'enum TextError:' / 'interface TextError:', declare it as a type parameter, or import it
// expect-error: MS2001 10:43 unknown binding TextError; declare it with 'TextError := ...' before use, define 'fn TextError(...) T { ... }', or import it from a module
