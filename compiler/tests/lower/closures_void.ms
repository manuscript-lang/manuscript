fn nop(n: Int) Void:
	return

fn side(x: Int) Int:
	p := fn(y: Int) Void:
		return
	p(x)
	nop(x)
	return x

export fn main() Int:
	return side(3) + use_borrows().length()

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

fn borrows(s: String, t: String) String:
	g := fn(x: Int) String:
		return s + t
	return g(1)

fn use_borrows() String:
	return borrows("a", "b")
