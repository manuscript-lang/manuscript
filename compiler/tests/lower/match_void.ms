fn note(n: Int) Void:
	return

fn pick(n: Int) Int:
	var total = 0
	match n:
		1: total = total + 10
		2: note(n)
		_: total = total + 1
	return total

fn main() Int:
	return pick(1) + pick(2) + pick(3)
