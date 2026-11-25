// conform: tags=control-flow,diagnostics,tier-core
// conform: phase=check
// conform: origin=pkg/parser/parser_test.go:202 TestInlineSuites
fn f() Void {
	if true {
		return
	} else {
		return
	}
}
