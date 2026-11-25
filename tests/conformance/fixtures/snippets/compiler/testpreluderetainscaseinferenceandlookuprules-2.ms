// conform: tags=diagnostics,tier-core
// conform: phase=check
// conform: origin=pkg/compiler/prelude_test.go:13 TestPreludeRetainsCaseInferenceAndLookupRules
fn f() Void {
	result := ok(value: 1)
}
// expect-error: MS3080 5:15 cannot infer constructor type argument E; write the type arguments, e.g. Box[Int](...), or annotate the binding
