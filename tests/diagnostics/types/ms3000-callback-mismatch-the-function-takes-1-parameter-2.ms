// conform: tags=diagnostics
// conform: phase=check
fn start[T](operation fn() T) Int {
	return 0
}

fn work(n Int) Int {
	return n
}

fn f() Int {
	return start(work)
}
// expect-error: MS3000 12:18 callback mismatch: the function takes 1 parameter but this position expects 0; pass a function with 0 parameters, or wrap it in a closure that supplies the rest
