// conform: tags=diagnostics
// conform: phase=check
fn caller() Result[Int, Error] {
	return match operation() {
		ok(value) => operation()
		error(cause) => operation()
	}
}
// expect-error: MS2001 4:18 unknown binding operation; declare it with 'operation := ...' before use, define 'fn operation(...) T { ... }', or import it from a module
