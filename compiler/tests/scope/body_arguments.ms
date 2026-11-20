// Call arguments: one past the last parameter is reported, a mismatch names the argument.
fn double(n: Int) Int:
	return n * 2

fn extra() Int:
	return double(1, 2)

fn wrong() Int:
	return double("one")

fn fine() Int:
	return double(double(2))
