fn twice(f: fn(Int) Int, x: Int) Int:
	return f(f(x))

fn scale(k: Float, x: Float) Float:
	g := fn(v: Float) Float:
		return v * k
	return g(x)

fn two_lambdas(a: Int, b: Int) Int:
	inc := fn(x: Int) Int:
		return x + a
	dec := fn(x: Int) Int:
		return x - b
	return twice(inc, 1) + twice(dec, 10)

fn nested(n: Int) Int:
	outer := fn(x: Int) Int:
		inner := fn(y: Int) Int:
			return x + y + n
		return inner(2)

	return outer(3)

fn shout(x: Int) Void:
	return

fn pick(flag: Bool) Int:
	h := fn(x: Int) Int:
		return x * 3
	return twice(h, 2)

fn side(flag: Bool) Void:
	p := fn(x: Int) Void:
		return
	p(1)

export fn main() Int:
	return two_lambdas(1, 2) + nested(4) + pick(true)
