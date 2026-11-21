fn empty(xs: List[Int]) Bool:
	return xs.is_empty()

fn finite(x: Float) Bool:
	return x.is_finite()

fn not_a_number(x: Float) Bool:
	return x.is_nan()

fn main() Int:
	xs := [1]
	if empty(xs) or finite(1.0) or not_a_number(2.0): return 1

	return 0
