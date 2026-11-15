// removed: fn f(ref x: List[Int]) ...
// use: returns a borrow of it, with no marker
// fix: fn first(xs: List[Int])
fn first(ref xs: List[Int]) Int:
	return xs[0]
fn main() Int:
	return 0
