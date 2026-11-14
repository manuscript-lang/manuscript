import (
	stdin from "@std/io/io.ms",
	read_all from "@std/io/streams.ms",
)

fn main() Unit:
	data := read_all(stdin(), none).get().decode_utf8().get("")
	var lines = Map[String, Int]()
	var names = Map[String, Int]()
	var total = 0

	for line in data.split("\n"):
		if line.is_empty(): continue

		total += 1
		lines.update(line.clone(), 0, fn v: v + 1)

		name := line.split(" ", 2)[0].clone()
		names.update(name.clone(), 0, fn v: v + 1)

	var most = ""
	var most_count = 0

	for e in lines.entries():
		if e.value > most_count or e.value == most_count and e.key.compare(most) < 0:
			most = e.key.clone()
			most_count = e.value

	print("lines: {total}")
	print("distinct lines: {lines.length()}")
	print("distinct names: {names.length()}")
	print("most repeated: {most} x{most_count}")
