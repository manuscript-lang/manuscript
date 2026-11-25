// removed: name: Type
// use: remove the ':' between 'a' and its type
// fix: fn f(a Int) Int {
fn f(a: Int) Int {
	return a
}
fn main() Int {
	return f(1)
}
