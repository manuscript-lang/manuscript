fn first(xs: List[Int]) Int:
	return xs[0]

fn sum_two(xs: List[Int]) Int:
	return xs[0] + xs[1]

fn build(a: Int, b: Int) List[Int]:
	return [a, b, a + b]

fn local_list() Int:
	xs := [1, 2, 3]
	return xs[1]

fn annotated() Int:
	xs: List[Float] := [1.5, 2.5]
	n := xs[0]
	return 1

fn moved(xs: List[Int]) List[Int]:
	ys := xs
	return ys

fn used_after(xs: List[Int]) Int:
	ys := xs
	return ys[0] + xs[0]

fn strings(a: String, b: String) List[String]:
	return [a, b]

fn strings_reused(a: String) List[String]:
	return [a, a]

fn nested(a: Int) List[List[Int]]:
	return [[a], [a, a]]
