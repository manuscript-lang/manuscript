fn describe(name: String, count: Int) String:
	return f"{name} has {count} items"

fn sum3(a: String, b: String, c: String) String:
	return a + b + c

fn long(a: String, n: Int) String:
	text := f"{a},{n},{a},{n},{a},{n},{a},{n}"
	return text

fn mixed(a: String, b: String) String:
	return a + f"<{b}>" + "!"

fn main() Int:
	text := describe("x", 3)
	more := sum3(text, "y", "z")
	other := long(more, 2)
	last := mixed(other, text)
	return 0
