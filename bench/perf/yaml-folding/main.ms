import (
	parse, stringify from "@std/data/yaml.ms",
	arguments from "@std/os/env.ms",
	StringBuilder from "@std/string.ms",
	monotonic from "@std/time.ms",
)

fn main() Unit!:
	args := arguments()
	n := args[0].parse_int().get()
	repeats := args[1].parse_int().get()
	var text = StringBuilder()
	text.append("[")
	for i in 0..n:
		text.append("\n  word")
	text.append("\n]\n")

	input := text.build()
	expected := stringify(parse(input)?)?
	var total = 0
	start := monotonic()

	for unused in 0..repeats:
		value := parse(input)?
		total += (stringify(value)?).byte_length()

	ns := monotonic().difference(start).to_nanoseconds()
	if total != expected.byte_length() * repeats: return error(Error("checksum"))

	print("{ns} {total}")
