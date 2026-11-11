import (
	stdout from "@std/io/io.ms",
	arguments from "@std/os/env.ms",
	read_file, write_file from "@std/os/fs.ms",
	monotonic from "@std/time.ms",
)

fn main() Int:
	args := arguments()
	path := args[0]
	text := read_file(path).wait().get().decode_utf8().get()
	count := args[1].parse_int().get()
	expected := text

	if count == 0:
		stdout().write(expected).get()
		return 0

	// Optional readiness marker for the external-input observability probe, outside timing.
	if args.length() > 2:
		write_file(args[2], "ready").wait().get()

	var checksum = 0
	start := monotonic()

	for unused in 0..count:
		current := read_file(path).wait().get().decode_utf8().get()
		output := current
		if output != expected: return 1

		checksum += output.byte_length()

	elapsed := monotonic().difference(start).to_nanoseconds()
	print("{elapsed}\t{checksum}\t{expected.byte_length()}")
	return 0
