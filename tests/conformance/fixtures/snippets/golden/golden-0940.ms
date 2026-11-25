// conform: tags=diagnostics
// conform: phase=check
fn f() Void {
	g := fn(x Int) Int => return x
	use(fn(x Int) Int => return x, other: 1)

	gs := [fn() Void => return, fn() Int => return 2]
}
// expect-error: MS2001 5:5 unknown binding use; declare it with 'use := ...' before use, define 'fn use(...) T { ... }', or import it from a module
// expect-error: MS3001 7:33 expected fn() Void, found fn() Int (in entry 2 of the literal, whose entries share one type)
