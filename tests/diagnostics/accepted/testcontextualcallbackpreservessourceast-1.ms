// conform: tags=closures,diagnostics,formatter,records,tier-core
// conform: phase=check,parse
// conform: origin=pkg/checker/checker_test.go:55 TestContextualCallbackPreservesSourceAST
type Callback {
	value fn(Int) Int
}

fn example() Void {
	_callback := Callback(value => value + 1)
}
// expect-exit: 0
