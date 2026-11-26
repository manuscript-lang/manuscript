// conform: tags=aliasing,closures,formatter,parser,strings,tier-core,try-result
// conform: phase=parse
// conform: origin=pkg/compiler/contextual_generics_test.go:98 TestExpectedResultGenericInferenceRejects
fn first() Void {
	value fn(String) Int!Error := fail
}
// expect-format: rewritten
// expect-formatted: fn first() Void {
// expect-formatted: \tvalue fn(String) Int! := fail
// expect-formatted: }
