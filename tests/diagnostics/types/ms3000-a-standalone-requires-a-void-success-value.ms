// conform: tags=diagnostics
// conform: phase=check
fn p() Result[Int, Error] {
	return ok(1)
}

fn f(x Int?) Result[Void, Error] {
	match x {
		n => {
			p()?
			return ok()
		}
		null => return ok()
	}
}
// expect-error: MS3000 10:13 a standalone '?' requires a Void success value, found Int; use 'name := call()?' to keep the value or 'return call()?' to return it
