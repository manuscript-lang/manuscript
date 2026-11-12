import (
	stderr from "@std/io/io.ms",
	arguments from "@std/os/env.ms",
	Timestamp, monotonic from "@std/time.ms",
)

fn main() Unit!:
	args := arguments()
	pattern := args[0]
	zone := args[1]
	repeats := args[2].parse_int().get()
	stamp := Timestamp(args[3].parse_int().get(), args[4].parse_int().get())
	expected := stamp.format(pattern, zone)?
	stderr().write("{expected}\n")?

	var checksum = 0
	start := monotonic()

	for unused in 0..repeats:
		result := stamp.format(pattern, zone)?
		checksum += result.byte_length()

	ns := monotonic().difference(start).to_nanoseconds()
	if checksum != expected.byte_length() * repeats:
		return error(Error("format checksum mismatch"))

	print("{ns} {checksum}")
