fn count(n: Int) Int:
	if n < 2: return 1
	return pair(n) + 1

fn pair(n: Int) Int:
	return count(n - 1) + count(n - 2)

fn main() Unit:
	print("{count(32)}")
