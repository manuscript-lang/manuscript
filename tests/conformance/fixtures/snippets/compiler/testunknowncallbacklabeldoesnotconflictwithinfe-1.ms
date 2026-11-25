// conform: tags=closures,diagnostics,tier-core
// conform: phase=check
// conform: origin=pkg/compiler/callbacks_test.go:140 TestUnknownCallbackLabelDoesNotConflictWithInference
fn example() Void {
	choose(first: () => "a", second: () => "b", other: () => missing)
}
