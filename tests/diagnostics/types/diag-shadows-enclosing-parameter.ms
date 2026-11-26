// conform: tags=diagnostics,control-flow,tier-core
// conform: phase=check
// conform: origin=ms-check/tests/messages.rs
fn f(x Int) Int {
	if x > 0 {
		x := 2
		return x
	}

	return 0
}

export fn main() Int {
	return f(1)
}
// expect-error: MS3000 6:9 binding x shadows an outer binding of the same name; rename one of them, or assign to the outer 'var'
