// removed: optional.get(default)
// use: get_or
// fix: .get_or(
fn main() Int:
	o: Int? := none
	return o.get(1)
