fn a(x: Int?) Int:
	return x.get_or(7)

fn b(d: Int, x: Int?) Int:
	return x.get_or(d + 1)

fn c(x: Int!) Int:
	return x.get_or(3)

fn main() Int:
	return a(1) + b(2, none) + c(ok(1))
