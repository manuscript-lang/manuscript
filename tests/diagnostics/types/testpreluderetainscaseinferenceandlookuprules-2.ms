// conform: tags=diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=pkg/compiler/prelude_test.go:13 TestPreludeRetainsCaseInferenceAndLookupRules
fn f() Void {
	result := ok(value: 1)
}
// expect-error: MS3080 5:15 cannot infer constructor type argument E; write the type arguments, e.g. Box[Int](...), or annotate the binding
