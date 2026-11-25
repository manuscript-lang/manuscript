// conform: tags=diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=pkg/checker/defaults_test.go:49 TestDefaultsDoNotMutateSourceAST
fn f(value Int = 3) Int {
	return value
}

fn call() Int {
	return f()
}
// expect-exit: 0
