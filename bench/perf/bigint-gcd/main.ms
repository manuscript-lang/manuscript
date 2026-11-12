import (
	parse from "@std/math/math.ms",
	arguments from "@std/os/env.ms",
	monotonic from "@std/time.ms",
)

fn main() Int:
	args := arguments()
	if args.length() != 6: return 2

	a := parse(args[0], 10, none).get()
	alternate := parse(args[1], 10, none).get()
	b := parse(args[2], 10, none).get()
	expected := parse(args[3], 10, none).get()
	expected_alt := parse(args[4], 10, none).get()
	repeats := args[5].parse_int().get()
	if repeats < 1 or repeats > 100000000: return 2

	var checks = 0
	start := monotonic()

	for i in 0..repeats:
		if i % 2 == 0:
			result := a.gcd(b)
			if result != expected: return 3
		else:
			result := alternate.gcd(b)
			if result != expected_alt: return 3

		checks += 1

	elapsed := monotonic().difference(start).to_nanoseconds()
	print("{elapsed} {checks}")
	return 0
