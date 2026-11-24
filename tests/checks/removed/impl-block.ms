// removed: impl Type:
// use: fn Type.name(
// fix: none: the methods must be moved out of the block by hand
type A {
	n Int
}
impl A {
	fn f(self) Int {
		return 1
	}
}
fn main() Int {
	return 0
}
