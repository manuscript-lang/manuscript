// conform: tags=diagnostics
// conform: phase=check
fn f(second Int, first Int = 1) Int {
	return first + second
}

fn call() Int {
	return f()
}
// expect-error: MS3003 8:12 missing argument second: Int in call to f; add 'second: <Int>'
