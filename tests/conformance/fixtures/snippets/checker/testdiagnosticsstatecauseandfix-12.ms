// conform: tags=closures,diagnostics,formatter,generics,tier-core
// conform: phase=check,parse
// conform: origin=pkg/checker/hints_test.go:31 TestDiagnosticsStateCauseAndFix
fn start[T](operation fn() T) Int {
	return 0
}

fn work(n Int) Int {
	return n
}

fn f() Int {
	return start(work)
}
// expect-error: MS3000 13:18 callback mismatch: the function takes 1 parameter but this position expects 0; pass a function with 0 parameters, or wrap it in a closure that supplies the rest
