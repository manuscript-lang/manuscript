// conform: tags=diagnostics
// conform: phase=check
fn operation() Void => void

fn f() Result[Int, Error] {
	operation()?
	return ok(1)
}
// expect-error: MS3000 6:5 '?' requires a Result or an Optional, found Void; apply '?' to a value of type Result[T, E] or T?
