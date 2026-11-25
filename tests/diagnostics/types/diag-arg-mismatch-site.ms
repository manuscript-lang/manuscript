// conform: tags=diagnostics,types,tier-core
// conform: phase=check
// conform: origin=ms-check/tests/messages.rs
fn f(a Int) Int {
	return a
}

export fn main() Int {
	return f("s")
}
// expect-error: MS3001 9:14 expected Int, found String (in argument 'a' of f)
