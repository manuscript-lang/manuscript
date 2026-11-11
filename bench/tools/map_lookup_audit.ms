// Longer paired trials for one flagged case from set-empty-relations/maps-control.ms.
import (
	arguments from "@std/os/env.ms",
	monotonic from "@std/time.ms",

	capture, ensure_directory, finish, invalid, write_text from "./lib.ms",
)

fn run(args: List[String]) String!:
	if args.length() != 8: return invalid(
		"expected BEFORE AFTER OUTPUT PAIRS MODE SIZE REPEATS PREFIX_WIDTH"
	)

	pairs := args[3].parse_int().get(0)
	n := args[5].parse_int().get(-1)
	repeats := args[6].parse_int().get(0)
	width := args[7].parse_int().get(-1)
	if pairs < 1 or n < 0 or repeats < 1 or width < 0: return invalid(
		"invalid numeric argument"
	)

	prefix := "a".repeat(width)?
	want := n * (n - 1) * repeats
	ensure_directory(args[2])

	var rows = ["trial,version,inner_ns,wall_ns,checksum"]

	for sample in 0..pairs + 1:
		order := if sample % 2 == 0: [0, 1] else: [1, 0]

		for version in order:
			start := monotonic()
			ran := capture(
				args[version], [args[4].clone(), "{n}", "{repeats}", prefix.clone()]
			)
			wall := monotonic().difference(start).to_nanoseconds()
			if not ran.ok or ran.code != 0 or ran.stderr != "": return invalid(
				"producer failed: {ran.code} {ran.stderr}"
			)

			parts := ran.stdout.trim().split(" ")
			if parts.length() != 2: return invalid("invalid producer output")

			elapsed := parts[0].parse_int().get(0)
			actual := parts[1].parse_int().get(-1)
			if elapsed <= 0 or actual != want: return invalid(
				"invalid timing or checksum"
			)

			rows.append("{sample - 1},{version},{elapsed},{wall},{actual}")

		write_text("{args[2]}/samples.csv", rows.join("\n") + "\n")

	write_text("{args[2]}/complete.txt", "all producers and checksums passed\n")
	return ok("completed {rows.length() - 1} validated producer runs")

fn main() Int:
	return finish(run(arguments()))
