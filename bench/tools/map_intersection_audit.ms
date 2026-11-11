// Paired runtime Set intersection/algebra controls. Producers verify exact ordered
// members. Usage: ms run bench/tools/map_intersection_audit.ms -- BEFORE AFTER_OR_DASH
// OUTPUT PAIRS WORK [MODE [PATTERN [SIZE]]]
import (
	arguments from "@std/os/env.ms",
	monotonic from "@std/time.ms",

	capture, ensure_directory, finish, invalid, write_text from "./lib.ms",
)

fn checksum(mode: String, pattern: String, n: Int) Int:
	all := n * (n + 1) / 2
	one := if n > 0: n / 2 + 1 else: 0

	if mode == "intersection":
		if pattern == "same": return all
		if pattern == "one": return one

		return 0

	if pattern == "holes": return (n / 2) * (n / 2 + 1)

	if mode == "difference":
		if pattern == "same": return 0
		if pattern == "one": return all - one

	if mode == "union" and pattern == "disjoint": return n * (2 * n + 1)

	return all

fn run(args: List[String]) String!:
	if args.length() < 5 or args.length() > 8: return invalid(
		"expected BEFORE AFTER_OR_DASH OUTPUT PAIRS WORK [MODE [PATTERN [SIZE]]]"
	)

	out := args[2]
	pairs := args[3].parse_int().get(0)
	work := args[4].parse_int().get(0)
	if pairs < 1 or work < 1: return invalid("positive pairs and work required")

	ensure_directory(out)

	var rows = ["mode,pattern,size,repeats,trial,version,inner_ns,wall_ns,checksum"]

	for mode in ["intersection", "union", "difference"]:
		if args.length() > 5 and args[5] != mode: continue

		for pattern in ["empty", "same", "disjoint", "one", "holes"]:
			if args.length() > 6 and args[6] != pattern: continue

			for n in [0, 1, 8, 128, 4096, 65536]:
				if args.length() > 7 and args[7] != "{n}": continue

				count := if n > 0: work / n else: work
				repeats := if count < 1: 1 else: count
				want := checksum(mode, pattern, n) * repeats

				for sample in 0..pairs + 1:
					order := if sample % 2 == 0: [0, 1] else: [1, 0]

					for version in order:
						if version == 1 and args[1] == "-": continue

						start := monotonic()
						ran := capture(
							args[version],
							[
								mode.clone(),
								"{n}",
								"{repeats}",
								pattern.clone(),
							],
						)
						wall := monotonic().difference(start).to_nanoseconds()
						if not ran.ok or ran.code != 0 or ran.stderr != "": return invalid(
							"producer failed: {mode} {pattern} {n}: {ran.code} {ran.stderr}"
						)

						parts := ran.stdout.trim().split(" ")
						if parts.length() != 2: return invalid(
							"invalid producer output"
						)

						elapsed := parts[0].parse_int().get(0)
						actual := parts[1].parse_int().get(-1)
						if elapsed <= 0 or actual != want: return invalid(
							"invalid timing or checksum: {mode} {pattern} {n}"
						)

						rows.append(
							"{mode},{pattern},{n},{repeats},{sample - 1},{version},{elapsed},{wall},{actual}"
						)

				write_text("{out}/samples.csv", rows.join("\n") + "\n")

	if rows.length() == 1: return invalid("no cases matched")

	write_text("{out}/complete.txt", "all producers and checksums passed\n")
	return ok("completed {rows.length() - 1} validated producer runs")

fn main() Int:
	return finish(run(arguments()))
