fn show(n: Int) Int:
	return n

fn kind(n: Int) Int:
	match n:
		0: show(1)
		_: show(2)

	return 3

fn main() Int:
	return kind(1)
