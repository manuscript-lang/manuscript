// conform: tags=diagnostics
// conform: phase=check
fn operation() Result[Void, Error] => ok()

fn caller() Void {
	operation()
}
// expect-error: MS3000 6:5 this statement discards Void!, so a failure would be lost; write a trailing '?' to propagate it, 'if value := x' or 'match' to handle it, or 'void ...' to drop it on purpose
