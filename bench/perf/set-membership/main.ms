import (
	SortedMap from "@std/collections/sorted.ms",
	arguments from "@std/os/env.ms",
	monotonic from "@std/time.ms",
)

fn main() Int:
	args := arguments()
	mode := args[0]
	n := args[1].parse_int().get()
	repeats := args[2].parse_int().get()
	shape := args[3].parse_int().get()
	if n < 0 or n > 65536 or repeats < 0 or repeats > 100000000: return 2

	var mapped = Map[Int, Int]()
	var set = Set[Int]()
	var sorted = SortedMap[Int, Int]()

	if mode == "set":
		for i in 0..n: set.add(i * 17)
	else if mode == "mapped":
		for i in 0..n: mapped.add(i * 17, i)
	else:
		for i in 0..n: sorted.add(i * 17, i)

	if mode == "layout":
		for chunk in sorted.key_chunks: print("{chunk.length()}")
		return 0

	var checksum = 0
	start := monotonic()

	if mode == "set":
		for r in 0..repeats:
			base := if n == 0: 0 else: ((r * 104729) % n) * 17
			key := if shape == 2: n * 17 + 17 + r % 17 else if shape == 3: -17 - r % 17 else: base + shape
			if set.contains(key): checksum += 1
	else if mode == "mapped":
		for r in 0..repeats:
			base := if n == 0: 0 else: ((r * 104729) % n) * 17
			key := if shape == 2: n * 17 + 17 + r % 17 else if shape == 3: -17 - r % 17 else: base + shape
			if mapped.contains(key): checksum += 1
	else if mode == "query":
		for r in 0..repeats:
			base := if n == 0: 0 else: ((r * 104729) % n) * 17
			key := if shape == 2: n * 17 + 17 + r % 17 else if shape == 3: -17 - r % 17 else: base + shape
			checksum += key
	else:
		for r in 0..repeats:
			base := if n == 0: 0 else: ((r * 104729) % n) * 17
			key := if shape == 2: n * 17 + 17 + r % 17 else if shape == 3: -17 - r % 17 else: base + shape
			if sorted.contains(key): checksum += 1

	elapsed := monotonic().difference(start).to_nanoseconds()
	print("{elapsed} {checksum}")
	return 0
