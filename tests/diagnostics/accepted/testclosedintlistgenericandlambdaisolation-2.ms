// conform: tags=closures,control-flow,diagnostics,formatter,mutation,tier-core
// conform: phase=check,parse
// conform: origin=pkg/compiler/list_bounds_test.go:74 TestClosedIntListGenericAndLambdaIsolation
fn probe(value Int) Int {
	values := [1, 2, 3]

	callback := fn() Int {
		var sum = value
		for item in values {
			sum += item
		}
		return sum
	}

	return callback()
}
// expect-exit: 0
