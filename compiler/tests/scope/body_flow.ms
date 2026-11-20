// Paths that end without a value, a bare return in a function with one, and `not` on a
// number.
fn falls(n: Int) Int:
	if n > 0: return 1

fn bare(n: Int) Int:
	if n > 0: return
	return 2

fn negated(n: Int) Bool:
	return not n

fn fine(n: Int) Bool:
	return not (n == 0)
