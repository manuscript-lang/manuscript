// Owned-string filtering followed by metadata lookup, with the same numeric oracle as
// intersection.ms.
import (
	arguments from "@std/os/env.ms",
	monotonic from "@std/time.ms",
)

fn operation(a: Set[String], b: Set[String], mode: String) Set[String]:
	if mode == "union": return a.union(b)
	if mode == "difference": return a.difference(b)

	return a.intersection(b)

fn main() Int:
	args := arguments()
	mode := args[0]
	n := args[1].parse_int().get()
	repeats := args[2].parse_int().get()
	pattern := args[3]
	var a = Set[String]()
	var b = Set[String]()
	var expected = List[String]()
	var keys = List[String]()
	var metadata = Map[String, Int]()

	for i in 0..n * 2:
		key := "workspace/documents/record-{i}/read-permission"
		keys.append(key.clone())
		metadata.add(key.clone(), i + 1)
		if i < n: a.add(key.clone())
		if pattern == "same" and i < n: b.add(key.clone())
		if pattern == "disjoint" and i >= n: b.add(key.clone())

	if pattern == "one" and n > 0: b.add(keys[n / 2].clone())
	if pattern == "holes":
		for i in 0..n:
			if i % 2 == 0: a.remove(keys[i].clone())

	for i in 0..n:
		left := pattern != "holes" or i % 2 == 1
		right := pattern == "same" or (pattern == "one" and i == n / 2)
		if not left: continue

		if mode == "union" or (mode == "difference" and not right):
			expected.append(keys[i].clone())
		else if mode == "intersection" and right:
			expected.append(keys[i].clone())

	if mode == "union" and pattern == "disjoint":
		for i in n..n * 2: expected.append(keys[i].clone())

	probe := operation(a, b, mode)
	if probe.values() != expected: return 3

	var expected_sum = 0
	for value in expected: expected_sum += metadata.get_or(value, -1)

	var checksum = 0
	start := monotonic()

	for iteration in 0..repeats:
		result := operation(a, b, mode)
		for value in result.values(): checksum += metadata.get_or(value, -1)

	elapsed := monotonic().difference(start).to_nanoseconds()
	if checksum != expected_sum * repeats: return 4

	print("{elapsed} {checksum}")
	return 0
