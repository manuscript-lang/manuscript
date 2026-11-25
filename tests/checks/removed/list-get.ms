// removed: list.get(index)
// use: write xs[i]
// fix: none: the receiver is any expression, so the edit is made by hand
fn main() Int {
	xs := [1, 2, 3]
	return xs.get(1)
}
