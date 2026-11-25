// conform: tags=control-flow,diagnostics,formatter,mutation,tier-core
// conform: phase=check,parse
// conform: origin=pkg/compiler/list_bounds_test.go:89 TestClosedIntListGenericAndLambdaIsolation
fn probe() Int {
	values := [1, 2, 3]
	var sum = 0
	for item in values {
		sum += item
	}
	return sum + values.length()
}
// expect-exit: 0
