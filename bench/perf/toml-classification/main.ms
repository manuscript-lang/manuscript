import (
	TomlValue, parse, stringify from "@std/data/toml.ms",
	stderr from "@std/io/io.ms",
	arguments from "@std/os/env.ms",
	StringBuilder from "@std/string_builder.ms",
	monotonic from "@std/time.ms",
)

fn main() Unit!:
	args := arguments()
	kind := args[0]
	n := args[1].parse_int().get()
	repeats := args[2].parse_int().get()
	var text = StringBuilder()

	if kind == "tables":
		for i in 0..n:
			text.append(
				"[[items]]\nname = 'item-{i}'\nnumber = {i}\n[items.meta]\nactive = true\n"
			)
	else if kind == "mixed":
		text.append("items = [")

		for i in 0..n:
			if i > 0: text.append(",")
			text.append("\{name='item-{i}',number={i}\}")

		text.append(", 1]\n")
	else if kind == "array":
		text.append("items = [")

		for i in 0..n:
			if i > 0: text.append(",")
			text.append("{i}")

		text.append("]\n")
	else:
		text.append("name = 'ordinary é🙂'\nactive = true\ncount = 7\n")

	value := parse(text.build())?
	expected := stringify(value)?
	stderr().write(expected)?

	var sum = 0
	start := monotonic()

	for unused in 0..repeats:
		out := stringify(value)?
		sum += out.byte_length()

	ns := monotonic().difference(start).to_nanoseconds()
	if sum != expected.byte_length() * repeats: return error(Error("checksum"))

	print("{ns} {sum}")
