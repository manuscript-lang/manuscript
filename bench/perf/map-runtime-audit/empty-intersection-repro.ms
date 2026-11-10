import (
	arguments from "@std/os/env.ms",
	monotonic from "@std/time.ms",
)

fn main() Int:
	n := arguments()[0].parse_int().get()
	var left = Set[Int]()
	for i in 0..n: left.add(i)

	right := Set[Int]()
	var checksum = 0
	start := monotonic()
	for i in 0..1000: checksum += left.intersection(right).length()
	print("{monotonic().difference(start).to_nanoseconds()} {checksum}")
	return if checksum == 0: 0 else: 1
