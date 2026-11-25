// conform: tags=closures,diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=pkg/parser/parser_test.go:203 TestInlineSuites
fn f() Void {
	g := fn(x Int) Int => return x
	use(fn(x Int) Int => return x, other: 1)

	gs := [fn() Void => return, fn() Int => return 2]
}
// expect-error: MS2001 6:5 unknown binding use; declare it with 'use := ...' before use, define 'fn use(...) T { ... }', or import it from a module
// expect-error: MS3001 8:33 expected fn() Void, found fn() Int (in entry 2 of the literal, whose entries share one type)
