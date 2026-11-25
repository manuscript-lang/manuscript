// conform: tags=diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=pkg/tooling/lsp/scheduling_test.go:62 TestQueuedChangesPreserveRangesVersionsAndErrors
// alpha beta
fn answer() Int {
	return 2
}
// expect-exit: 0
