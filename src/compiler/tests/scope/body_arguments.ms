// Call arguments: one past the last parameter is reported, a mismatch names the
// argument.
fn double(n: Int) Int:
	return n * 2

fn extra() Int:
	return double(1, 2)

fn wrong() Int:
	return double("one")

fn fine() Int:
	return double(double(2))

fn named() Int:
	return double(n: 3)

fn missing() Int:
	return double()

fn pair(a: Int, b: Int) Int:
	return a + b

fn missing_second() Int:
	return pair(1)

fn labelled_wrong() Int:
	return pair(a: 1, c: 2)
