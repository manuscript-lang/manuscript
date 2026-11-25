// conform: tags=diagnostics,formatter,match,optional,tier-core
// conform: phase=check,parse
// conform: origin=pkg/tooling/lsp/features_test.go:178 TestWildcardBindingsRemainSafeAcrossEditorFeatures
fn answer(value Int?) Int {
	match value {
		_value => {
			return 1
		}
		null => {
			return 0
		}
	}
}
// expect-exit: 0
