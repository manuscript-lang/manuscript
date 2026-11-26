// conform: tags=diagnostics
// conform: phase=check
fn f() Void {
	for [key, value] in entries {
		return
	}
}
// expect-error: MS2001 4:25 unknown binding entries; declare it with 'entries := ...' before use, define 'fn entries(...) T { ... }', or import it from a module
// expect-error: MS3000 4:9 positional binding requires a list; use [a, b] patterns only with List values
