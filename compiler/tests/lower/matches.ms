fn tier(n: Int) Int:
	return match n:
		0: 10
		-1: 20
		_: 30

fn pick(flag: Bool) Int:
	return (if flag: 1 else: 2)

fn sum(n: Int, f: Bool) Int:
	base := match n:
		1: 100
		2: 200
		3: 300
		4: 400
		_: n

	return base + (if f: 1 else: 0)

fn main() Int:
	return tier(3) + pick(true) + sum(2, false)
