// conform: tags=diagnostics
// conform: phase=check
fn f() Int {
	v := x
		| f  // first
		// explain
		| g(a: 1)
		| .size()
	return 0
}
// expect-error: MS2001 7:11 unknown binding g; declare it with 'g := ...' before use, define 'fn g(...) T { ... }', or import it from a module
