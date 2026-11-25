// conform: tags=diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=pkg/lexer/positions_test.go:17 TestMixedLineEndingPositions
// first
fn value() Int {
	return 1
}
// expect-exit: 0
