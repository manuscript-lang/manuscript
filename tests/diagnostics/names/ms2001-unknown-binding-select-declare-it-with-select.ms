// conform: tags=diagnostics
// conform: phase=check
fn run() Int {
	return select[Int](1, last: 3, value => value + 1)
}
// expect-error: MS2001 4:12 unknown binding select; declare it with 'select := ...' before use, define 'fn select(...) T { ... }', or import it from a module
