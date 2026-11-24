// removed: fn x: expr
// use: a one-line closure is written without 'fn'
// fix: none: moving the parameters before '=>' is not a one-token edit
fn main() Int:
	xs := [1, 2]
	return xs.map(fn x: x + 1).length()
