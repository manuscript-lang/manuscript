// conform: tags=diagnostics,tier-core
// conform: phase=check
fn f() Result[Int, Error] {
	return ok(1)
}

fn g() Result[Int, Error] {
	v := try f()
	return ok(v)
}
// expect-error: MS1000 8:10-8:17 'try' was replaced by a postfix '?': write f(x)? instead of try f(x), and x | step? instead of x | try step
// expect-fix: 8:10-8:17 "f()?"
