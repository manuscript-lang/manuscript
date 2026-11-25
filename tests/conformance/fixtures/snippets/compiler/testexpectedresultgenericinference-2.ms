// conform: tags=closures,diagnostics,optional,tier-core
// conform: phase=check
// conform: origin=pkg/compiler/contextual_generics_test.go:45 TestExpectedResultGenericInference
fn first() Void {
	callback fn() Int? := () => absent()
}
// expect-error: MS2001 5:33 unknown binding absent; declare it with 'absent := ...' before use, define 'fn absent(...) T { ... }', or import it from a module
