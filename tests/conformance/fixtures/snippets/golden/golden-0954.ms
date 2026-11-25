// conform: tags=diagnostics
// conform: phase=check
fn f(x Int?) Result[Void, Error] {
	match x {
		n => {
			g(n)?
			return ok()
		}
		null => return ok()
	}
}
// expect-error: MS2001 6:13 unknown binding g; declare it with 'g := ...' before use, define 'fn g(...) T { ... }', or import it from a module
