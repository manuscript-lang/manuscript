// conform: tags=diagnostics,tier-core
// conform: phase=check
fn f(x Int) Int! {
	if x < 0 {
		return error("negative")
	}
	return ok(x)
}

export fn main() Int {
	print(f(1).is_error())
	return 0
}
