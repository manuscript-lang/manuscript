// conform: tags=diagnostics
// conform: phase=check
fn p() Result[Int, Error] {
	return ok(1)
}

fn f() Int {
	return p()
}
// expect-error: MS3001 8:12 expected Int, found Int! (in the return value); unwrap it with a trailing '?' inside a function that returns a compatible Result, with 'if value := x', or with '.get()'
