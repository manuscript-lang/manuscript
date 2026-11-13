import (
	stdin, stdout from "@std/io/io.ms",
	read_all from "@std/io/streams.ms",
	StringBuilder from "@std/string_builder.ms",
)

fn main() Unit:
	data := read_all(stdin(), none).get().decode_utf8().get("")
	var out = StringBuilder()
	var total = 0

	for line in data.split("\n"):
		if line.is_empty(): continue

		f := line.split(" ")
		score := f[1].parse_int().get(0)
		total += score
		out.append(
			"{f[0].pad_end(12, " ")} {score.to_string().pad_start(8, " ")} {score * 3 / 7}\n"
		)

	out.append("total {total}\n")
	stdout().write(out.build()).get()
