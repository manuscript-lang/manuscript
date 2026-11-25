// conform: tags=control-flow,diagnostics,formatter,strings,tier-core
// conform: phase=check,parse
// conform: origin=pkg/lexer/positions_test.go:14 TestMixedLineEndingPositions
// é😀
fn value() String {
	// comment
	if true {
		return "é😀"
	}
	return ""
}
// expect-exit: 0
