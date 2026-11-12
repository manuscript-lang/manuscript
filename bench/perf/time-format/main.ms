import (
	arguments from "@std/os/env.ms",
	monotonic, parse_timestamp from "@std/time.ms",
)

fn main() Int?!:
	args := arguments()
	pattern := args[0]
	zone := args[1]
	repeats := args[2].parse_int().get()
	stamp := parse_timestamp("2024-02-29T23:59:59.123456789Z")?
	expected := stamp.format(pattern, zone)?
	var checksum = 0
	start := monotonic()

	for unused in 0..repeats:
		result := stamp.format(pattern, zone)?
		checksum += result.byte_length()

	ns := monotonic().difference(start).to_nanoseconds()
	if checksum != expected.byte_length() * repeats: return ok(1)

	print("{ns} {checksum}")
	return ok(0)
