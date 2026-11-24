// conform: tags=testing,tier-core
// conform: phase=check
fn main() Void {
	var xs = [1, 2]
	each := xs.for_each
	each((var n) => n += 1)
}
