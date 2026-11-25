// conform: tags=ownership,tier-core
// conform: phase=check
// `x or default` takes what it is given: a borrowed parameter needs `.clone()` or `move`. (`ok(x)` of a `&T!` result wraps a view.)
fn pick(hold name String?) &String {
	return name or "none"
}

fn main() Void {
	print(pick("a"))
}
// expect-error: MS3000 5:12 `name` is a view of another value, not an owner, and cannot be moved here; take the owner with `move`, or pass `name.clone()`
