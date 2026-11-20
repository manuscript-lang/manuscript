// Assigning an immutable binding is reported, and the value is still checked.
fn bump(x: Int) Int:
	n := x
	n = 2
	return n

fn widen(x: Float) Float:
	m := x
	m = 3
	return m
