// conform: tags=diagnostics,tier-core
// conform: phase=check
fn load() Int! {
	return ok(1)
}

fn run() Int! {
	v := try load() + 1
	return ok(v)
}
// expect-error: MS1000 8:10-8:13 'try' was replaced by a postfix '?': write f(x)? instead of try f(x), and x | step? instead of x | try step
