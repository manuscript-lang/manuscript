fn pick(a: String, b: String, first: Bool) String:
	if first: return a
	return b

fn echo(s: String) String:
	return s

fn alias(a: String) Int:
	b := a
	return b.length() + a.length()

fn main() Int:
	x := pick("ab", "cd", true)
	y := echo(x)
	if y == "ab": return alias(x)

	return 1
