fn down(n: Int) Int:
	return down(n + 1) + n

fn main() Int:
	return down(0)
