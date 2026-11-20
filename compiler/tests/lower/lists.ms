fn first(xs: List[Int]) Int:
	return xs[0]

fn make() List[Int]:
	return [4, 5]

fn flags() List[Bool]:
	return [true, false]

fn floats(i: Int) Bool:
	xs := [1.5, 2.5]
	return xs[i] > 2.0

fn empty() List[Int]:
	return []

fn pass(move xs: List[Int]) List[Int]:
	return xs

fn main() Int:
	xs := [1, 2, 3]
	zs := make()
	f := flags()
	n := pass(make())
	if f[1] or floats(1): return 1
	return xs[1] + first(xs) + zs[0] + first(n) + first([1]) + first(empty())
