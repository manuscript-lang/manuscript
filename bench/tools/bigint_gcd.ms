// Compare two prebuilt public BigInt GCD programs. Build both from main.ms in
// bench/perf/bigint-gcd with their respective compilers before running this driver.
import (
	arguments from "@std/os/env.ms",
	read_file from "@std/os/fs.ms",

	capture, fail, maximum, median, minimum from "./lib.ms",
)

fn sample(binary: String, fields: List[String], repeats: Int) Int:
	args := [
		"-c",
		"0",
		binary.clone(),
		fields[1].clone(),
		fields[2].clone(),
		fields[3].clone(),
		fields[4].clone(),
		fields[5].clone(),
		repeats.to_string(),
	]
	ran := capture("taskset", args)

	if not ran.ok or ran.code != 0:
		print(ran.stderr)
		return -1

	parts := ran.stdout.trim().split(" ")
	if parts.length() != 2: return -1
	if parts[1].parse_int().get(-1) != repeats: return -1

	return parts[0].parse_int().get(-1)

fn main() Int:
	args := arguments()
	if args.length() < 2 or args.length() > 4:
		return fail("usage: bigint_gcd.ms -- BEFORE AFTER [CYCLES] [CASE]")

	var cycles = 11
	if args.length() > 2: cycles = args[2].parse_int().get(0)
	if cycles < 2: return fail("cycles must include warmup and at least one pair")

	text := (
		read_file("bench/perf/bigint-gcd/cases.tsv")
		.wait()
		.get()
		.decode_utf8()
		.get()
	)
	var selected = 0
	print("kind\tcase\tcycle\tbinary\trepeats\tnanoseconds")

	for line in text.trim().split("\n"):
		fields := line.split("\t")
		if fields.length() != 7: return fail("invalid case row")

		name := fields[0]
		if args.length() > 3 and name != args[3]: continue

		selected += 1

		repeats := fields[6].parse_int().get(0)
		if repeats < 1: return fail("invalid repeat count")

		var ratios = List[Float]()
		var before_samples = List[Float]()
		var after_samples = List[Float]()

		for cycle in 0..cycles:
			var before = 0
			var after = 0

			for slot in 0..2:
				index := if cycle % 2 == 0: slot else: 1 - slot
				elapsed := sample(args[index], fields, repeats)
				if elapsed < 0: return fail("sample failed: {name}")

				print("sample\t{name}\t{cycle}\t{index}\t{repeats}\t{elapsed}")

				if index == 0:
					before = elapsed
				else:
					after = elapsed

			if cycle > 0:
				ratios.append(after.to_float() / before.to_float())
				before_samples.append(before.to_float() / repeats.to_float())
				after_samples.append(after.to_float() / repeats.to_float())

		print(
			"ratio\t{name}\t{median(ratios)}\t{minimum(ratios)}\t{maximum(ratios)}\t{median(before_samples)}\t{median(after_samples)}"
		)

	if selected == 0: return fail("no matching cases")

	return 0
