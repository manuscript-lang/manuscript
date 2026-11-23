import (
	stdin from "@std/io/io.ms",
	read_all from "@std/io/streams.ms",
)

fn main() Void:
	data := read_all(stdin(), null).get().decode_utf8().get_or("")
	var hits = 0
	for line in data.split("\n"):
		if line.contains(" POST /api/v2/item/17") and line.contains(" 500 "):
			hits += 1
	print(f"hits: {hits}")
