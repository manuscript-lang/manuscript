import (
	arguments from "@std/os/env.ms",
	monotonic from "@std/time.ms",
)

fn main() Int:
	args := arguments()
	mode := args[0]
	n := args[1].parse_int().get()
	repeats := args[2].parse_int().get()
	var values = List[Int]()
	var left = Set[Int]()
	var right = Set[Int]()

	for i in 0..n:
		values.append(i % (n / 2 + 1))
		left.add(i)
		right.add(i + n / 2)

	var checksum = 0
	start := monotonic()

	if mode == "convert":
		for r in 0..repeats: checksum += values.to_set().length()
	else:
		for r in 0..repeats: checksum += left.union(right).length()

	elapsed := monotonic().difference(start).to_nanoseconds()
	print("{elapsed} {checksum}")
	return 0
