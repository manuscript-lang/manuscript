// conform: tags=diagnostics
// conform: phase=check
fn caller() Result[Int, Error] {
	value := operation()
	return value
}
// expect-error: MS2001 4:14 unknown binding operation; declare it with 'operation := ...' before use, define 'fn operation(...) T { ... }', or import it from a module
