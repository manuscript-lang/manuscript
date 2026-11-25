// conform: tags=control-flow,diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=pkg/parser/parser_test.go:200 TestInlineSuites
fn f(x Int) Int {
	if x > 0 {
		return x
	} else {
		return 0
	}
}
// expect-exit: 0
