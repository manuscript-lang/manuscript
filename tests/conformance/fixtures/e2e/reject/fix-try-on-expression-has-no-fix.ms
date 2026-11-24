// conform: tags=diagnostics,tier-core
// conform: phase=check
fn load() Int! {
	return ok(1)
}

fn run() Int! {
	v := try load() + 1
	return ok(v)
}
