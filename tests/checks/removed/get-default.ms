// removed: optional.get(default)
// use: get_or
// fix: .get_or(
fn main() Int:
	o Int? := null
	return o.get(1)
