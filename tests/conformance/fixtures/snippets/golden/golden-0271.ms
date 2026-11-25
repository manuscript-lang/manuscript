// conform: tags=diagnostics
// conform: phase=check
fn p() Result[Int, Error] {
	return ok(1)
}

fn f() Int {
	return p() + 1
}
// expect-error: MS3001 8:16 operator operands require the same independently known type, found Result[Int, Error] + Int; unwrap it with a trailing '?' inside a function that returns a compatible Result, with 'if value := x', or with '.get()'
