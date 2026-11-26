// conform: tags=formatter,parser,tier-core,try-result
// conform: phase=parse
// conform: origin=pkg/compiler/contextual_generics_test.go:38 TestExpectedResultGenericInference
fn first() Void {
	result Int!Error := fail("empty")
}
// expect-format: rewritten
// expect-formatted: fn first() Void {
// expect-formatted: \tresult Int! := fail("empty")
// expect-formatted: }
