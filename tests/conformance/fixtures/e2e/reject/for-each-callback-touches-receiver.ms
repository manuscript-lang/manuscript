// conform: tags=testing,tier-core
// conform: phase=check
fn main() Unit:
	var xs = [1, 2]
	xs.for_each(fn var n: xs.append(n))
