// conform: tags=closures,formatter,parser,tier-core
// conform: phase=parse
// conform: origin=pkg/compiler/contextual_generics_test.go:90 TestExpectedResultGenericInferenceRejects
fn first() Void {
	callback fn(Int) Int := from_callback(() => fn(value Int = 4) => value)
	callback()
}
