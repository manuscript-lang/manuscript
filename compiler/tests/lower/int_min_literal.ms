fn lowest() Int:
	return -9223372036854775808

fn compare(x: Int) Bool:
	return x == -9223372036854775808

fn main() Int:
	low := -9223372036854775808
	if compare(low): return 0

	return lowest() + 1
