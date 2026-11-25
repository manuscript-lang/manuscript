// conform: tags=closures,diagnostics,records,tier-core
// conform: phase=check
// conform: origin=pkg/checker/checker_test.go:55 TestContextualCallbackPreservesSourceAST
type Callback {
	value fn(Int) Int
}

fn example() Void {
	_callback := Callback(value => value + 1)
}
// expect-exit: 0
