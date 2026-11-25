// conform: tags=diagnostics
// conform: phase=check
fn f(value Int = 1) Int {
	return value
}

fn apply(callback fn(Int) Int) Int {
	return callback()
}
// expect-error: MS3003 8:12 missing argument 1: Int in call to callback; pass it positionally, without a label
