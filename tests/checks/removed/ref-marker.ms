// removed: fn f(ref x List[Int]) ...
// use: 'ref' is not a parameter marker
// fix: fn first(xs List[Int]) Int {
fn first(ref xs List[Int]) Int {
	return xs[0]
}
fn main() Int {
	return 0
}
