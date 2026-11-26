// conform: tags=diagnostics
// conform: phase=check
fn first() Int {
	r Result[Int, Error] := f()
	return h(r)
}
// expect-error: MS2001 4:29 unknown binding f; declare it with 'f := ...' before use, define 'fn f(...) T { ... }', or import it from a module
// expect-error: MS2001 5:12 unknown binding h; declare it with 'h := ...' before use, define 'fn h(...) T { ... }', or import it from a module
