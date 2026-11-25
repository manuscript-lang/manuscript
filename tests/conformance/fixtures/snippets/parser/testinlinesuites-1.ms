// conform: tags=closures,diagnostics,tier-core
// conform: phase=check
// conform: origin=pkg/parser/parser_test.go:198 TestInlineSuites
fn f() Void {
	use(value => value + 1)
}
// expect-error: MS2001 5:5 unknown binding use; declare it with 'use := ...' before use, define 'fn use(...) T { ... }', or import it from a module
