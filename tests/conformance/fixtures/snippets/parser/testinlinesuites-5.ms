// conform: tags=control-flow,diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=pkg/parser/parser_test.go:202 TestInlineSuites
fn f() Void {
	if true {
		return
	} else {
		return
	}
}
// expect-exit: 0
