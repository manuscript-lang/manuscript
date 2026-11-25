// conform: tags=diagnostics
// conform: phase=check
fn value() Int {
	return sum(left: read(1), right: 2)
}
// expect-error: MS2001 4:12 unknown binding sum; declare it with 'sum := ...' before use, define 'fn sum(...) T { ... }', or import it from a module
