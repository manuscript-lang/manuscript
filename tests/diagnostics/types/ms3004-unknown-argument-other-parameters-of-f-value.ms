// conform: tags=diagnostics
// conform: phase=check
fn f(value Int = 1) Int {
	return value
}

fn call() Int {
	return f(other: 3)
}
// expect-error: MS3004 8:14 unknown argument other; parameters of f: value
