// conform: tags=diagnostics,tier-core
// conform: phase=check
fn f() Result[Int, Error] {
	return ok(1)
}

fn g() Result[Int, Error] {
	v := try f()
	return ok(v)
}
