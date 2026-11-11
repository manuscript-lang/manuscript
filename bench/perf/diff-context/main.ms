import (
	UnifiedDiffOptions, unified_diff from "@std/data/diff.ms",
	arguments from "@std/os/env.ms",
	monotonic from "@std/time.ms",
)

fn main() Int:
	args := arguments()
	n := args[0].parse_int().get()
	context := args[1].parse_int().get()
	repeats := args[2].parse_int().get()
	mode := args[3]
	var old: List[String] = []
	var new: List[String] = []

	for i in 0..n:
		new.append("line {i}")
		if mode != "insert": old.append("line {i}")

	if mode == "sparse": new[n / 2] = "changed"

	options := UnifiedDiffOptions(context: context)
	expected := unified_diff(old, new, options)
	start := monotonic()
	var sum = 0

	for unused in 0..repeats:
		output := unified_diff(old, new, options)
		if output != expected: return 1

		sum += output.length()

	print("{monotonic().difference(start).to_nanoseconds()} {sum}")
	return 0
