// conform: tags=closures,diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=pkg/compiler/contextual_generics_test.go:87 TestExpectedResultGenericInferenceRejects
fn first() fn(Int) Int {
	callback := fn(item Int) => item
	return identity(callback)
}
// expect-error: MS2001 6:12 unknown binding identity; declare it with 'identity := ...' before use, define 'fn identity(...) T { ... }', or import it from a module
