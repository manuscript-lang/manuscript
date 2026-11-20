fn sign(x: Int) Int:
	if x < 0: return -1
	if x > 0: return 1

	return 0

fn pick(flag: Bool, a: Int, b: Int) Int:
	if flag:
		y := a * 2
		return y + b
	else:
		return b - a

fn clamp(x: Int, lo: Int, hi: Int) Int:
	if x < lo:
		return lo
	else:
		if x > hi:
			return hi
		else:
			return x

fn forever(x: Int) Int:
	while true:
		if x > 3: return x
		return 0

fn never(x: Int) Int:
	while x < 0:
		return 1
	return 2

fn main() Int:
	return sign(3) + pick(true, 1, 2) + clamp(5, 0, 3) + forever(4) + never(1)
