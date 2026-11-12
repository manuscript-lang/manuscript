import (
	stdin from "@std/io/io.ms",
	read_all from "@std/io/streams.ms",
)

fn main() Unit:
	data := read_all(stdin(), none).get().decode_utf8().get("")
	var hits = 0
	for line in data.split("\n"):
		if line.contains(" POST /api/v2/item/17") and line.contains(" 500 "):
			hits += 1
	print("hits: {hits}")
