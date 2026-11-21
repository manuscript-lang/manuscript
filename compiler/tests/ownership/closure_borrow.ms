fn same(s: String, t: String) Bool:
	return s == t

fn apply(f: fn(Int) Bool, x: Int) Bool:
	return f(x)

fn read(s: String, t: String) Bool:
	g := fn(x: Int) Bool:
		return s == t
	return g(1) and apply(g, 2)

fn changed() Bool:
	var s = "a"
	g := fn(x: Int) Bool:
		return s == "b"
	s = "c"
	return g(1)

fn moved(s: String) Bool:
	t := s
	g := fn(x: Int) Bool:
		return t == "b"
	u := t
	return g(1)

fn returned(s: String) fn(Int) Bool:
	g := fn(x: Int) Bool:
		return s == "b"
	return g
