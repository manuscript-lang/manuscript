fn add(a: Int, b: Int) Int:
	sum := a + b
	return sum * 2

fn twice(x: Int) Int:
	y := add(x, 1)
	return add(y, x)

fn main() Void:
	n := 3
	print(twice(n))
