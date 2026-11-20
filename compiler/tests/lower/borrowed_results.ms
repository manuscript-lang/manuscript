fn pick(a: String, b: String, first: Bool) String:
	if first: return a
	return b

fn echo(s: String) String:
	return s

fn main() Int:
	x := pick("ab", "cd", true)
	y := echo(x)
	if y == "ab": return 0

	return 1
