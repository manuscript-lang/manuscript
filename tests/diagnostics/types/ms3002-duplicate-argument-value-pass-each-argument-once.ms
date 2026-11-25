// conform: tags=diagnostics
// conform: phase=check
fn f(value Int = 1) Int {
	return value
}

fn call() Int {
	return f(2, value: 3)
}
// expect-error: MS3002 8:17 duplicate argument value; pass each argument once
