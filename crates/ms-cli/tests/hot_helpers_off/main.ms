import stdout from "@std/io/io.ms"

fn say(text: String) Void:
	_ignored := stdout().write(text)

fn probe(a: String, b: String) Int:
	var n = 0
	i := a.index_of(b)
	if i.is_some():
		n += i.get_or(0)
	n += a.view(1, 3).length()
	n += a.parse_int().get_or(100)
	return n

fn main() Void:
	say(f"{probe("hello", "ll")} {probe("12345", "34")} {probe("abcdefg", "zz")}\n")
