// conform: tags=control-flow,diagnostics,formatter,match,optional,tier-core
// conform: phase=check,parse
// conform: origin=pkg/build/expression_conveniences_test.go:13 TestExpressionConvenienceRejections
fn f(x Int?) Int {
	while true {
		while (
			match x {
				n => true
				null => break
			}
		) {
			break
		}
	}
}
// expect-error: MS3000 4:1 reachable fallthrough in function returning Int; end every path with 'return <Int>' (or make the last branch return)
