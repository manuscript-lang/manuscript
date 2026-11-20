fn count(xs: List[Int]) Int:
	return xs.length()

fn nothing(xs: List[Int]) Bool:
	return xs.is_empty()

fn second(xs: List[Int]) Int:
	return xs.get(1)

fn pick(xs: List[Int], i: Int) Int:
	return xs.get_or(i, 7)

fn ratio(xs: List[Float]) Float:
	return xs.get_or(-1, 0.5)

fn fresh() Int:
	return [4, 5, 6].length() + [1, 2].get(0)

fn main() Int:
	xs := [1, 2]
	ys := [1.5]
	if nothing(xs): return 0
	if ratio(ys) > 3.0: return 1

	return count(xs) + second(xs) + pick(xs, 5) + pick(xs, -1) + fresh()
