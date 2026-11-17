// removed: get(default) on the result of a call
// use: get_or
// fix: .get_or(
fn pick() Int?:
	return 1

fn main() Int:
	return pick().get(2)
