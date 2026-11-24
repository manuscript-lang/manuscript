// conform: tags=testing,tier-core
// conform: phase=check
fn main() Void:
	var xs = [1, 2]
	xs.for_each((var n) => xs.append(n))
