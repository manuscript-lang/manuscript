// conform: tags=diagnostics
// conform: phase=check
fn f() Void {
	use(
		fn(value, other Int) {
			return value + other
		}
	)
}
// expect-error: MS2001 4:5 unknown binding use; declare it with 'use := ...' before use, define 'fn use(...) T { ... }', or import it from a module
