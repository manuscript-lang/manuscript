import (
	parse from "@std/data/json.ms",
	arguments from "@std/os/env.ms",
	monotonic from "@std/time.ms",
)

extern fn codec_bench_cpu_ns() Int

fn main() Int:
	args := arguments()
	size := args[0].parse_int().get()
	rounds := args[1].parse_int().get()
	shape := args[2]
	valid := shape.ends_with("valid")
	typed := shape.starts_with("typed")
	var expected = ""
	var input = ""

	if valid: input += "\""
	else: input += "]"

	for i in 0..size:
		expected += "a"

		if shape.ends_with("escaped"): input += "\\"
		else: input += "a"

	if valid: input += "\""

	wanted := expected
	text := input
	var checksum = 0
	cpu_start := codec_bench_cpu_ns()
	if cpu_start < 0: return 4

	start := monotonic()

	for i in 0..rounds:
		if typed:
			result := parse[String](text)

			if valid:
				if result.is_error(): return 2
				if result.get() != wanted: return 8
			else:
				if result.is_ok(): return 3
				if result.err().kind != "EBADMSG": return 5
		else:
			result := parse(text)

			if valid:
				if result.is_error(): return 2

				parsed := result.get()
				if not parsed.as_string().is_some(): return 7
				if parsed.as_string().get_or("") != wanted: return 8
			else:
				if result.is_ok(): return 3
				if result.err().kind != "EBADMSG": return 5

		checksum += 1

	elapsed := monotonic().difference(start).to_nanoseconds()
	cpu := codec_bench_cpu_ns() - cpu_start
	if cpu <= 0: return 6

	print(f"{size} {rounds} {shape} {checksum} {elapsed} {cpu}")
	return 0
