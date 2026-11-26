// conform: tags=closures,diagnostics,formatter,mutation,tier-core
// conform: phase=check,parse
// conform: origin=pkg/compiler/contextual_generics_test.go:93 TestExpectedResultGenericInferenceRejects
fn required(value Int) Int => value

fn first() Void {
	var callback fn(Int) Int = from_callback(() => fn(value Int = 4) => value)
	callback = required
	callback()
}
// expect-error: MS2001 7:32 unknown binding from_callback; declare it with 'from_callback := ...' before use, define 'fn from_callback(...) T { ... }', or import it from a module
// expect-error: MS3003 9:5 missing argument 1: Int in call to callback; pass it positionally, without a label
