// conform: tags=diagnostics
// conform: phase=check
fn f() Int {
	while foo(a) {
		if b {
			return 1
		}
		return 2
	}

	return 3
}
// expect-error: MS2001 4:11 unknown binding foo; declare it with 'foo := ...' before use, define 'fn foo(...) T { ... }', or import it from a module
// expect-error: MS2001 5:12 unknown binding b; declare it with 'b := ...' before use, define 'fn b(...) T { ... }', or import it from a module
