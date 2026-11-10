import (
	combinations from "@std/collections/itertools.ms",
	arguments from "@std/os/env.ms",
	monotonic from "@std/time.ms",
)

fn main() Int:
	args := arguments()
	n := args[0].parse_int().get()
	k := args[1].parse_int().get()
	repeats := args[2].parse_int().get()
	expected := args[3].parse_int().get()
	var input: List[Int] = []
	for i in 0..n: input.append(i)

	start := monotonic()
	var checksum = 0

	for unused in 0..repeats:
		output := combinations(input, k)
		if output.length() != expected: return 1

		checksum += output.length()

	print("{monotonic().difference(start).to_nanoseconds()} {checksum}")
	return 0
