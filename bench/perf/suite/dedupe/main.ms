import (
	stdin from "@std/io/io.ms",
	read_all from "@std/io/streams.ms",
)

fn main() Void {
	data := read_all(stdin(), null).get().decode_utf8() or ""
	var lines = Map[String, Int]()
	var names = Map[String, Int]()
	var total = 0

	for line in data.split("\n") {
		if line.is_empty() { continue }

		total += 1
		lines.update(line, 0, v => v + 1)

		name := line.split(" ")[0].clone()
		names.update(name, 0, v => v + 1)
	}

	var most = ""
	var most_count = 0

	for e in lines.entries() {
		if e.value > most_count or e.value == most_count and e.key.compare(most) < 0 {
			most = e.key.clone()
			most_count = e.value
		}
	}

	print(f"lines: {total}")
	print(f"distinct lines: {lines.length()}")
	print(f"distinct names: {names.length()}")
	print(f"most repeated: {most} x{most_count}")
}
