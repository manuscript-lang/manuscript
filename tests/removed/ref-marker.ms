// removed: fn f(ref x: List[Int]) ...
// use: expected ':' between 'ref' and its type
// fix: none: `ref` is an ordinary name now, so no mechanical edit applies; drop the word by hand
fn first(ref xs: List[Int]) Int:
	return xs[0]
fn main() Int:
	return 0
