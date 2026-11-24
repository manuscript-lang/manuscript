import (
	stdin from "@std/io/io.ms",
	read_all from "@std/io/streams.ms",
)

fn main() Void:
	data := read_all(stdin(), null).get().decode_utf8() or ""
	var counts = Map[String, Int]()
	var total = 0

	for word in data.lower().fields_by(fn c: c == " " or c == "." or c == "\n"):
		total += 1
		counts.update(word.clone(), 0, fn v: v + 1)

	print(f"words: {total}")
	print(f"distinct: {counts.length()}")
	for e in counts.entries().sorted(
		fn a,
		b: if a.value != b.value: b.value - a.value else: a.key.compare(b.key)
	).slice(0, 10).get():
		print(f"{e.key} {e.value}")
