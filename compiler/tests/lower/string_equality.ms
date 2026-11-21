fn same(a: String, b: String) Bool:
	return a == b

fn differ(a: String) Bool:
	return a != "abc"

fn main() Int:
	if same("a", "a") and differ("x"):
		return 1
	return 0
fn left(a: String) Bool:
	return "abc" == a

fn both() Bool:
	return "a" == "b"

fn eqs(a: String) Bool:
	return a == "abc"

fn probe(a: String) Int:
	if left(a) or both() or eqs(a):
		return 1
	return 0
