// conform: tags=control-flow,diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=pkg/lexer/lexer_test.go:14 TestLayoutAndLineEndings
// module
fn value() Int {
	// comment
	if true {
		return 3
	} else {
		return 4
	}
}
// expect-exit: 0
