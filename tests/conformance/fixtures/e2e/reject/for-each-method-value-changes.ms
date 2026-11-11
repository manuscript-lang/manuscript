// conform: tags=testing,tier-core
// conform: phase=check
fn main() Unit:
	var xs = [1, 2]
	each := xs.for_each
	each(fn var n: n += 1)
