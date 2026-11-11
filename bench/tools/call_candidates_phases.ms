// Native-build phase deltas and wall residual from MS_TIMINGS=1, excluding round0.
import (
	median, read_text from "./lib.ms",
	arguments from "@std/os/env.ms",
)

export fn main() Unit:
	args := arguments()
	var groups = Map[String, List[Float]]()
	var walls = Map[String, Float]()

	for row in read_text("{args[0]}/samples.tsv").split("\n"):
		if row == "" or row.starts_with("round\t"): continue

		fields := row.split("\t")
		walls.add("{fields[0]} {fields[1]}", fields[3].parse_float().get() / 1000000.0)

	for round in 1..args[1].parse_int().get() + 1:
		for label in ["before", "after"]:
			path := "{args[0]}/round-{round}-{label}-native-chain-8.stderr"
			var previous = 0.0

			for line in read_text(path).split("\n"):
				if not line.starts_with("ms-timings:"): continue

				parts := line.split(" done at ")
				key := "{parts[0]} delta {label}"
				value := parts[1].split("s")[0].parse_float().get() * 1000.0
				delta := value - previous
				previous = value

				if var values = groups[key]?:
					values.append(delta)
				else:
					groups.add(key, [delta])

			key := "wall minus native phases {label}"
			residual := walls["{round} {label}"] - previous

			if var values = groups[key]?:
				values.append(residual)
			else:
				groups.add(key, [residual])

	for key in groups.keys().sorted():
		values := groups[key]
		print(
			"{key} n={values.length()} median_ms={median(values)} min_ms={values.min().get()} max_ms={values.max().get()}"
		)
