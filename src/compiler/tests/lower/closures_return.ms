fn adder(n: Int) fn(Int) Int:
	return fn(x: Int) Int:
		return x + n

fn named_adder(n: Int) fn(Int) Int:
	g := fn(x: Int) Int:
		return x + n
	return g

fn use(n: Int) Int:
	f := adder(n)
	h := named_adder(n)
	return f(1) + h(2)

export fn main() Int:
	return use(5)
