// conform: tags=diagnostics,formatter,generics,tier-core
// conform: phase=check,parse
// conform: origin=pkg/checker/checker_test.go:33 TestOmittedLabelPreservesSourceAST
fn identity[T](hold value T) &T {
	return value
}

fn call() Int {
	return identity(3)
}
// expect-exit: 0
