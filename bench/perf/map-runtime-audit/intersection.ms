import (
	arguments from "@std/os/env.ms",
	monotonic from "@std/time.ms",
)

fn operation(a: Set[Int], b: Set[Int], mode: String) Set[Int]:
	if mode == "union": return a.union(b)
	if mode == "difference": return a.difference(b)

	return a.intersection(b)

fn main() Int:
	args := arguments()
	mode := args[0]
	n := args[1].parse_int().get()
	repeats := args[2].parse_int().get()
	pattern := args[3]
	var a = Set[Int]()
	var b = Set[Int]()
	var expected = List[Int]()

	for i in 0..n:
		a.add(i)
		if pattern == "same": b.add(i)
		if pattern == "disjoint": b.add(n + i)

	if pattern == "one" and n > 0: b.add(n / 2)
	if pattern == "holes":
		for i in 0..n:
			if i % 2 == 0: a.remove(i)

	for i in 0..n:
		left := pattern != "holes" or i % 2 == 1
		right := pattern == "same" or (pattern == "one" and i == n / 2)
		if not left: continue

		if mode == "union" or (mode == "difference" and not right):
			expected.append(i)
		else if mode == "intersection" and right:
			expected.append(i)

	if mode == "union" and pattern == "disjoint":
		for i in 0..n: expected.append(n + i)

	probe := operation(a, b, mode)
	if probe.values() != expected: return 3

	var expected_sum = 0
	for value in expected: expected_sum += value + 1

	var checksum = 0
	start := monotonic()

	for iteration in 0..repeats:
		result := operation(a, b, mode)
		for value in result.values(): checksum += value + 1

	elapsed := monotonic().difference(start).to_nanoseconds()
	if checksum != expected_sum * repeats: return 4

	print("{elapsed} {checksum}")
	return 0
