import (
	arguments from "@std/os/env.ms",
	monotonic from "@std/time.ms",
)

fn main() Int:
	args := arguments()
	mode := args[0]
	n := args[1].parse_int().get()
	repeats := args[2].parse_int().get()
	shape := args[3].parse_int().get()
	var set = Set[String]()
	var map = Map[Int, String]()
	var queries = List[String]()

	for i in 0..n:
		key := i * 17
		set.add("{key}")
		map.add(key, "value-{key}")
		queries.append("{key + shape}")

	var checksum = 0
	start := monotonic()

	if mode == "strings":
		for r in 0..repeats:
			at := (r * 104729) % n
			if set.contains(queries[at]): checksum += 1
	else:
		for r in 0..repeats:
			key := ((r * 104729) % n) * 17 + shape
			if map.contains(key): checksum += 1

	elapsed := monotonic().difference(start).to_nanoseconds()
	print("{elapsed} {checksum}")
	return 0
