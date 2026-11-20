fn quotient(a: Int, b: Int) Int:
	return a / b + a % b

fn ratio(a: Float, b: Float) Float:
	c := a / b
	return c - -1.5 + (a + b)

fn negative(a: Int) Int:
	var total = -7
	var other = + a
	return total * other - -a

fn chain(a: Int, b: Int, c: Int) Int:
	return a - b - c + a * b * c

fn main() Int:
	if ratio(1.0, 2.0) > 0.5: return quotient(7, 2) + negative(3) + chain(1, 2, 3)
	return 0
