fn apply(f: fn(Int) Int, x: Int) Int:
	return f(x)

fn twice(f: fn(Int) Int, x: Int) Int:
	return f(f(x))

fn double(x: Int) Int:
	return x * 2

fn captured(n: Int) Int:
	g := fn(x: Int) Int:
		return x + n
	return apply(g, 4) + g(1)

fn named() Int:
	return twice(double, 3)

fn inline_lambda(n: Int) Int:
	return apply(
		fn(x: Int) Int:
			y := x + n
			return y * y
		,
		2
	)

fn nested(n: Int) Int:
	outer := fn(x: Int) Int:
		inner := fn(y: Int) Int:
			return y + x + n
		return inner(1)

	return outer(2)

fn labelled(s: String) Int:
	len := fn(t: String) Int:
		return t.length()
	return len(s) + len(s)

fn moved_function(n: Int) Int:
	g := fn(x: Int) Int:
		return x + n
	h := g
	return h(1) + g(2)
