// conform: tags=aliasing,closures,diagnostics,strings,tier-core,try-result
// conform: phase=check
// conform: origin=pkg/compiler/contextual_generics_test.go:98 TestExpectedResultGenericInferenceRejects
fn first() Void {
	value fn(String) Int!Error := fail
}
// expect-error: MS2001 5:35 unknown binding fail; add: import fail from "@std/test/test.ms"
// expect-fix: 1:1-1:1 "import fail from \"@std/test/test.ms\"\n"
