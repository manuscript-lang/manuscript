// conform: tags=testing,tier-core
// conform: phase=check
fn main() Void {
	var xs = [1, 2]
	each := xs.for_each
	each((var n) => n += 1)
}
// expect-error: MS3000 5:16 this method takes a callback that can change the receiver's elements, so it cannot be used as a value; call it, or write a closure
