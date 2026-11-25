// conform: tags=diagnostics
// conform: phase=check
fn f() Int {
	if a {
		return 1
	} else if foo(a) {
		return 2
	}

	return 3
}
// expect-error: MS2001 4:8 unknown binding a; declare it with 'a := ...' before use, define 'fn a(...) T { ... }', or import it from a module
// expect-error: MS2001 6:15 unknown binding foo; declare it with 'foo := ...' before use, define 'fn foo(...) T { ... }', or import it from a module
