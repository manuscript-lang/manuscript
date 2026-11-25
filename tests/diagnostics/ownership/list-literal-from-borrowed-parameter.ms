// conform: tags=ownership,tier-core
// conform: phase=check
// A list literal makes a new owner of each element, so a borrowed element needs
// `.clone()`.
fn pair(name String) List[String] {
	return [name]
}

fn main() Void {
	print(pair("a").length())
}
// expect-error: MS3000 6:13 `name` is a view of another value, not an owner, and cannot be moved here; take the owner with `move`, or pass `name.clone()`
