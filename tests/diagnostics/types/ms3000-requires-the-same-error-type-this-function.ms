// conform: tags=diagnostics
// conform: phase=check
fn operation() Result[Void, Int] => ok()

fn f() Result[Int, Error] {
	operation()?
	return ok(1)
}
// expect-error: MS3000 6:5 '?' requires the same error type; this function returns Result[Int, Error] but the operand fails with Int, so change the return error type or translate the error with map_error
