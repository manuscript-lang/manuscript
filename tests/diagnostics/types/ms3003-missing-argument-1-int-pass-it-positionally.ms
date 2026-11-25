// conform: tags=diagnostics
// conform: phase=check
fn f(value Int = 1) Int {
	return value
}

fn make() fn(Int) Int {
	return f
}

fn call() Int {
	return make()()
}
// expect-error: MS3003 12:12 missing argument 1: Int; pass it positionally, without a label
