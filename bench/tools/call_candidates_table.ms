// Summarize process-cold samples; round 0 is retained but excluded as warm-up.
import (
	arguments from "@std/os/env.ms",

	median, read_text from "./lib.ms",
)

export fn main() Unit:
	args := arguments()
	var groups = Map[String, List[Float]]()

	for row in read_text(args[0]).split("\n"):
		if row == "" or row.starts_with("round\t"): continue

		fields := row.split("\t")
		if fields[0] == "0": continue

		key := "{fields[2]} {fields[1]}"
		value := fields[3].parse_float().get() / 1000000.0

		if var values = groups[key]?:
			values.append(value)
		else:
			groups.add(key, [value])

	for key in groups.keys().sorted():
		values := groups[key]
		print(
			"{key} n={values.length()} median_ms={median(values)} min_ms={values.min().get()} max_ms={values.max().get()}"
		)
