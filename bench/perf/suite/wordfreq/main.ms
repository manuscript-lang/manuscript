import (
	stdin from "@std/io/io.ms",
	read_all from "@std/io/streams.ms",
)

fn main() Void {
	data := read_all(stdin(), null).get().decode_utf8() or ""
	var counts = Map[String, Int]()
	var total = 0
	text := data.lower()
	var start = -1
	var i = 0

	for c in text.chars() {
		if c == " " or c == "." or c == "\n" {
			if start >= 0 {
				total += 1
				counts.update(text.view(start, i), 0, v => v + 1)
				start = -1
			}
		} else if start < 0 {
			start = i
		}

		i += 1
	}

	if start >= 0 {
		total += 1
		counts.update(text.view(start, i), 0, v => v + 1)
	}

	print(f"words: {total}")
	print(f"distinct: {counts.length()}")
	for e in counts.entries().sorted(
		(
			a,
			b,
		) => if a.value != b.value { b.value - a.value } else { a.key.compare(b.key) }
	).slice(0, 10).get() {
		print(f"{e.key} {e.value}")
	}
}
