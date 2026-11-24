// conform: tags=ownership,tier-core
// conform: phase=check
// `ok(x)` and `x or default` take what they are given: a borrowed parameter needs `.clone()` or `move`.
fn wrap(name String) String! {
	return ok(name)
}

fn pick(name String?) String {
	return name or "none"
}

fn main() Void {
	print(pick("a"))
	print(wrap("b").get())
}
