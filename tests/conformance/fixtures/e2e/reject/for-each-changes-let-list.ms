// conform: tags=testing,tier-core
// conform: phase=check
fn main() Void:
	xs := [1, 2]
	xs.for_each(fn var n: n += 1)
