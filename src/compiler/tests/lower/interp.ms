fn describe(name: String, count: Int) String:
	return f"{name} has {count} items"

fn sum3(a: String, b: String, c: String) String:
	return a + b + c

fn long(a: String, n: Int) String:
	text := f"{a},{n},{a},{n},{a},{n},{a},{n}"
	return text

fn mixed(a: String, b: String) String:
	return a + f"<{b}>" + "!"

fn shown(x: Float, ok: Bool, n: Int) String:
	return f"{x} {ok} {n}"

fn main() Int:
	text := describe("x", 3)
	more := sum3(text, "y", "z")
	other := long(more, 2)
	last := mixed(other, text)
	show := shown(1.5, true, 2)
	return 0
