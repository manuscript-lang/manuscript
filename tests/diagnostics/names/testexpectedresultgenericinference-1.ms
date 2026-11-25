// conform: tags=diagnostics,tier-core,try-result
// conform: phase=check
// conform: origin=pkg/compiler/contextual_generics_test.go:38 TestExpectedResultGenericInference
fn first() Void {
	result Int!Error := fail("empty")
}
// expect-error: MS2001 5:25 unknown binding fail; add: import fail from "@std/test/test.ms"
// expect-fix: 1:1-1:1 "import fail from \"@std/test/test.ms\"\n"
