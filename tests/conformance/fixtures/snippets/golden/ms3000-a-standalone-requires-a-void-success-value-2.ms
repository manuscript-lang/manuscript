// conform: tags=diagnostics
// conform: phase=check
fn operation() Result[Int, Error] => ok(1)

fn f() Result[Int, Error] {
	operation()?
	return ok(1)
}
// expect-error: MS3000 6:5 a standalone '?' requires a Void success value, found Int; use 'name := call()?' to keep the value or 'return call()?' to return it
