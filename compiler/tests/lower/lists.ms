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
	if f[1] or floats(1) or scores() > 5.0: return 1
	return xs[1] + first(xs) + zs[0] + first(n) + first([1]) + first(empty()) + total(xs) + firstbig(xs) + literal_loop()

fn total(xs: List[Int]) Int:
	var sum = 0
	for x in xs:
		sum += x
	return sum

fn firstbig(xs: List[Int]) Int:
	for x in xs:
		if x > 10: return x
		if x < 0: continue
		if x == 5: break
	return 0

fn literal_loop() Int:
	var sum = 0
	for x in [1, 2, 3]:
		sum += x
	for y in make():
		sum += y
	return sum

fn scores() Float:
	var best = 0.0
	for x in [1.5, 2.5]:
		if x > best:
			best = x
	return best
