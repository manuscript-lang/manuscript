// conform: tags=diagnostics
// conform: phase=check
fn f(second Int, first Int = 1) Int {
	return first + second
}

fn call() Int {
	return f()
}
