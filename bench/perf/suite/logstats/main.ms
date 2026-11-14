import (
	stdin from "@std/io/io.ms",
	read_all from "@std/io/streams.ms",
)

fn main() Unit:
	data := read_all(stdin(), none).get().decode_utf8().get("")
	var rows = 0
	var latency = 0
	var classes = [0].repeated(4)
	var paths = Map[String, Int]()

	for line in data.split("\n"):
		if line.is_empty(): continue

		f := line.split(" ")
		rows += 1
		latency += f[5].parse_int().get(0)

		cls := f[4].scalar_at(0) - 50
		classes[cls] += 1
		paths.update(f[3].clone(), 0, fn v: v + 1)

	print("lines: {rows}")
	print("status: 2xx={classes[0]} 3xx={classes[1]} 4xx={classes[2]} 5xx={classes[3]}")
	print("latency: {latency}")

	ranked := paths.entries().sorted(
		fn a,
		b: if a.value != b.value: b.value - a.value else: a.key.compare(b.key)
	)
	for e in ranked.slice(0, 5).get():
		print("{e.key} {e.value}")
