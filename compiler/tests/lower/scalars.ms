fn mix(a: Int, b: Int) Int:
	n := a * b - 3
	var m = n
	return m + a

fn neg(y: Float) Float:
	return -y * 2.0

fn less(a: Int, b: Int) Bool:
	return a < b

fn invert(ok: Bool) Bool:
	return not ok

fn greet(name: String) String:
	return name + "!"

fn main() Int:
	if less(mix(2, 3), 4) and invert(false): return 1
	if neg(1.5) > 0.0: return 2
	if greet("a") == "a!": return 3

	return 0
