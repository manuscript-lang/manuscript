// conform: tags=diagnostics
// conform: phase=check
fn operation() Result[Void, Error] => ok()

fn f() Void {
	operation()?
}
// expect-error: MS3000 6:5 '?' requires an enclosing Result; declare this function to return Result[T, E], or use 'if value := x', '.get_or(default)', or '.get()'
