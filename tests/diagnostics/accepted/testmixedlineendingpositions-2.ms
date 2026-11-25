// conform: tags=diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=pkg/lexer/positions_test.go:15 TestMixedLineEndingPositions
fn value(value Int) Int {
	return (value + 1)
}
// expect-exit: 0
