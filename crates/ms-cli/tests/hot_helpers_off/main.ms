import (
	stdout from "@std/io/io.ms",
)

fn say(text: String) Unit:
	_ignored := stdout().write(text)

fn probe(a: String, b: String) Int:
	var n = 0
	i := a.index_of(b)
	if i.is_some():
		n += i.get(0)
	n += a.view(1, 3).length()
	n += a.parse_int().get(100)
	return n

fn main() Unit:
	say("{probe("hello", "ll")} {probe("12345", "34")} {probe("abcdefg", "zz")}\n")
