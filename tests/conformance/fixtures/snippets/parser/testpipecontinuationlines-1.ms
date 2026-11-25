// conform: tags=diagnostics,tier-core
// conform: phase=check
// conform: origin=pkg/parser/pipe_test.go:55 TestPipeContinuationLines
fn f() Int {
	v := x
		| f  // first
		// explain
		| g(a: 1)
		| .size()
	return 0
}
// expect-error: MS2001 8:11 unknown binding g; declare it with 'g := ...' before use, define 'fn g(...) T { ... }', or import it from a module
