// conform: tags=control-flow,formatter,parser,tier-core
// conform: phase=parse
// conform: origin=pkg/parser/parser_test.go:202 TestInlineSuites
fn f() Void {
	if true {
		return
	} else {
		return
	}
}
