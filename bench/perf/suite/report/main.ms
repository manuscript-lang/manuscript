import (
	stdin, stdout from "@std/io/io.ms",
	read_all from "@std/io/streams.ms",
	StringBuilder from "@std/string_builder.ms",
)

fn main() Void:
	data := read_all(stdin(), null).get().decode_utf8().get_or("")
	var out = StringBuilder()
	var total = 0

	for line in data.split("\n"):
		if line.is_empty(): continue

		f := line.split(" ")
		score := f[1].parse_int().get_or(0)
		total += score
		out.append(
			f"{f[0].pad_end(12, " ")} {score.to_string().pad_start(8, " ")} {score * 3 / 7}\n"
		)

	out.append(f"total {total}\n")
	stdout().write(out.build()).get()
