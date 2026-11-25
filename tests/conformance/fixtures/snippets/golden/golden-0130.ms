// conform: tags=diagnostics
// conform: phase=check
fn f(x Int?) Int {
	y := match x {
		n => n
		null => 0
	}

	return n
}
// expect-error: MS2001 9:12 unknown binding n; declare it with 'n := ...' before use, define 'fn n(...) T { ... }', or import it from a module
