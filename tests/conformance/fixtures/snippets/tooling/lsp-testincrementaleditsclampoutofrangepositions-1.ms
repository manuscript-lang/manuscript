// conform: tags=diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=pkg/tooling/lsp/features_test.go:453 TestIncrementalEditsClampOutOfRangePositions
fn answer() Int {
	return 42
}
// expect-exit: 0
