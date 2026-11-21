fn apply(f: fn(Int) Int, x: Int) Int:
	return f(x)

fn add_n(n: Int) Int:
	g := fn(x: Int) Int:
		return x + n
	return apply(g, 4)

fn direct(x: Int) Int:
	return x * 2

fn named() Int:
	return apply(direct, 3)

export fn main() Int:
	return add_n(1) + named()
