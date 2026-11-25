// conform: tags=diagnostics,tier-core
// conform: phase=check
// conform: origin=pkg/compiler/prelude_test.go:12 TestPreludeRetainsCaseInferenceAndLookupRules
fn f() Void {
	missing := null
}
// expect-error: MS3080 5:16 cannot infer the type of null; give it a target, e.g. `x Int? := null`, or pass a value
