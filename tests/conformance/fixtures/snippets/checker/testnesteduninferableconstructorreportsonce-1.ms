// conform: tags=diagnostics,optional,tier-core
// conform: phase=check
// conform: origin=pkg/checker/nested_literal_test.go:127 TestNestedUninferableConstructorReportsOnce
fn f() Void {
	x := null
}
// expect-error: MS3080 5:10 cannot infer the type of null; give it a target, e.g. `x Int? := null`, or pass a value
