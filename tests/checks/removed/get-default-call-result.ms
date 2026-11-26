// removed: get(default) on the result of a call
// use: x or d
// fix: or 
fn pick() Int? {
	return 1
}

fn main() Int {
	return pick().get(2)
}
