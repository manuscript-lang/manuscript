// Matched ratios, excluding round0: FILE [forward|swap] [wall|cpu].
import (
	median, read_text, invalid from "./lib.ms",
	arguments from "@std/os/env.ms",
)

// At least95% binomial coverage for the median, assuming independent pairs.
export fn median_interval(values: List[Float]) List[Float]!:
	n := values.length()
	if n < 6 or n > 1000: return invalid(
		"median interval requires 6..1000 observations"
	)

	for value in values:
		if not value.is_finite() or value <= 0.0: return invalid(
			"expected positive finite ratios"
		)

	sorted := values.sorted()
	var probability = 1.0
	for unused in 0..n: probability *= 0.5

	var cumulative = probability
	var rank = 0

	while cumulative <= 0.025:
		rank += 1
		probability *= (n - rank + 1).to_float() / rank.to_float()
		cumulative += probability

	return ok([sorted[rank - 1], sorted[n - rank]])

fn finite_counter(text: String) Float!:
	if value := text.parse_float():
		if value.is_finite() and value >= 0.0: return ok(value)
	return invalid("expected a finite nonnegative measurement")

export fn summarize(text: String, swap: Bool = false, cpu: Bool = false) String!:
	lines := text.split("\n")
	header := "round\tlabel\tinput\twall_ns\tmax_resident_bytes\tinput_sha256"
	cpu_header := header + "\tuser_ns\tsystem_ns"
	if lines[0] != header and lines[0] != cpu_header: return invalid(
		"unexpected sample header"
	)
	if cpu and lines[0] != cpu_header: return invalid("CPU counters are absent")

	columns := lines[0].split("\t").length()
	var before = Map[String, Float]()
	var after = Map[String, Float]()
	var hashes = Map[String, String]()

	for row in lines.slice(1, lines.length()).get():
		if row == "": continue

		fields := row.split("\t")
		if fields.length() != columns: return invalid("unexpected sample column count")

		var round = -1
		if parsed := fields[0].parse_int(): round = parsed
		if round < 0: return invalid("invalid sample round")
		if fields[1] != "before" and fields[1] != "after": return invalid(
			"unknown sample label"
		)

		key := "{fields[2]}\t{round}"
		var value = try finite_counter(fields[3])

		if cpu:
			user := try finite_counter(fields[6])
			system := try finite_counter(fields[7])
			value = user + system

		if not value.is_finite() or value <= 0.0: return invalid(
			"measurement must be positive and finite"
		)

		if previous := hashes.get(fields[2]):
			if previous != fields[5]: return invalid("input hash changed")
		else:
			hashes.add(fields[2].clone(), fields[5].clone())

		if fields[1] == "before":
			if before.get(key).is_some(): return invalid("duplicate before sample")

			before.add(key, value)
		else:
			if after.get(key).is_some(): return invalid("duplicate after sample")

			after.add(key, value)

	if before.length() != after.length(): return invalid("incomplete pairs")

	var groups = Map[String, List[Float]]()

	for key in before.keys():
		if not after.get(key).is_some(): return invalid("incomplete pair")

		parts := key.split("\t")
		if parts[1] == "0": continue

		var ratio = after[key] / before[key]
		if swap: ratio = before[key] / after[key]
		if not ratio.is_finite() or ratio <= 0.0: return invalid("invalid ratio")

		input := parts[0].clone()

		if var values = groups[input]?:
			values.append(ratio)
		else:
			groups.add(input, [ratio])

	if groups.is_empty(): return invalid("no measured pairs")

	var report = ""

	for key in groups.keys().sorted():
		values := groups[key]
		interval := try median_interval(values)
		slower := values.filter(fn value: value > 1.0).length()
		report += "{key} n={values.length()} median_candidate_ratio={median(values)} median95_lower={interval[0]} median95_upper={interval[1]} min_ratio={values.min().get()} max_ratio={values.max().get()} candidate_slower={slower}\n"

	return ok(report)

export fn main() Unit!:
	args := arguments()
	if args.length() < 1 or args.length() > 3: return invalid(
		"expected FILE [forward|swap] [wall|cpu]"
	)
	if args.length() > 1 and args[1] != "forward" and args[1] != "swap": return invalid(
		"unknown pair order"
	)
	if args.length() > 2 and args[2] != "wall" and args[2] != "cpu": return invalid(
		"unknown metric"
	)

	result := try summarize(
		read_text(args[0]), args.length() > 1 and args[1] == "swap",
		args.length() > 2 and args[2] == "cpu"
	)
	print(result)
