import (
	stdin from "@std/io/io.ms",
	read_all from "@std/io/streams.ms",
)

fn main() Unit:
	raw := read_all(stdin(), none).get()
	var rows = 0
	var latency = 0
	var classes = [0].repeated(4)
	var paths = Map[String, Int]()
	n := raw.length()
	var p = 0
	var starts = [0].repeated(7)

	while p < n:
		var q = p
		var k = 1
		starts[0] = p

		while q < n and raw[q] != 10:
			if raw[q] == 32 and k < 7:
				starts[k] = q + 1
				k += 1

			q += 1

		if q > p:
			rows += 1

			var lat = 0
			for i in starts[5]..q:
				lat = lat * 10 + (raw[i].to_int() - 48)
			latency += lat

			cls := raw[starts[4]].to_int() - 50
			classes[cls] += 1

			key := raw.view(starts[3], starts[4] - 1).decode_utf8().get("")
			paths.update(key, 0, fn v: v + 1)

		p = q + 1

	print("lines: {rows}")
	print("status: 2xx={classes[0]} 3xx={classes[1]} 4xx={classes[2]} 5xx={classes[3]}")
	print("latency: {latency}")

	ranked := paths.entries().sorted(
		fn a,
		b: if a.value != b.value: b.value - a.value else: a.key.compare(b.key)
	)
	for e in ranked.slice(0, 5).get():
		print("{e.key} {e.value}")
