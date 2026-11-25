// conform: tags=closures,diagnostics,formatter,generics,tier-core
// conform: phase=check,parse
// conform: origin=pkg/checker/defaults_test.go:28 TestDefaultArgumentBoundaries
fn run[T](operation fn() T) T {
	return operation()
}

fn f(value Int = 1) Int {
	return value
}

fn call() Int {
	return run(f)
}
// expect-error: MS3000 13:16 callback mismatch: the function takes 1 parameter but this position expects 0; pass a function with 0 parameters, or wrap it in a closure that supplies the rest
// expect-error: MS3001 13:16 expected fn() Int, found fn(Int) Int (in argument 'operation' of run)
