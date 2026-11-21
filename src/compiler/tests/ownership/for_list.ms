fn total(xs: List[Int]) Int:
	var sum = 0
	for x in xs:
		sum += x
	return sum

fn nested(xs: List[Int], ys: List[Int]) Int:
	var sum = 0
	for x in xs:
		for y in ys:
			sum += x * y
	return sum

fn rebuilt() Int:
	var xs = [1, 2, 3]
	var sum = 0

	for x in xs:
		sum += x
		xs = [4, 5]

	return sum + xs[0]

fn moved() Int:
	xs := [1, 2, 3]
	var sum = 0
	for x in xs:
		sum += x
	return sum + xs[0]

fn literal() Int:
	var sum = 0
	for x in [1, 2, 3]:
		sum += x
	return sum
