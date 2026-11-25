// conform: tags=diagnostics
// conform: phase=check
fn consume(value Result[Int, Error]) Void => void

fn caller() Void {
	consume(operation())
}
// expect-error: MS2001 6:13 unknown binding operation; declare it with 'operation := ...' before use, define 'fn operation(...) T { ... }', or import it from a module
