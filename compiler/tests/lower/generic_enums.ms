enum Pair[T]:
	Both(first: T, second: T)
	Neither

fn make(x: Int) Pair[Int]:
	return Both(x, x + 1)

fn empty() Pair[Bool]:
	return Neither

fn sum(p: Pair[Int]) Int:
	return match p:
		Both(a, b): a + b
		Neither: 0

fn present(p: Pair[Bool]) Bool:
	return match p:
		Both(a, b): a and b
		Neither: false

fn main() Int:
	if present(empty()): return 1
	return sum(make(2))
