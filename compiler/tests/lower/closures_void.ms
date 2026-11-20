fn nop(n: Int) Void:
	return

fn side(x: Int) Int:
	p := fn(y: Int) Void:
		return
	p(x)
	nop(x)
	return x

export fn main() Int:
	return side(3)

fn apply_text(f: fn(String) String, s: String) String:
	return f(s)

fn same(s: String) String:
	return s

fn run_text(s: String) String:
	return apply_text(same, s)

fn lam_text(s: String) String:
	g := fn(t: String) String:
		return t
	return g(s)
