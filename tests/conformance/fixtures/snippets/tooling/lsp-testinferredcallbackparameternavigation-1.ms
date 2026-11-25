// conform: tags=closures,diagnostics,tier-core
// conform: phase=check
// conform: origin=pkg/tooling/lsp/callbacks_test.go:10 TestInferredCallbackParameterNavigation
fn answer() Void {
	_values := [1, 2].map(value => value + 1)
}
// expect-exit: 0
