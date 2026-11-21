fn spread(a: Int, b: Int) Int:
	return a.abs() + b.sign()

fn main() Void:
	print(spread(-3, 4))
