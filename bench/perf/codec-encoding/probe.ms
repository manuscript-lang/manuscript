import (
	Bytes from "@std/bytes.ms",
	panic from "@std/core.ms",
	base64_encode, hex_decode, hex_encode, utf16_decode from "@std/data/encoding.ms",
	arguments from "@std/os/env.ms",
	read_file from "@std/os/fs.ms",
	monotonic from "@std/time.ms",
)

fn hex(input: Bytes, expected: String, count: Int, kind: String, limit: Int) Int:
	var checksum = 0

	for unused in 0..count:
		result := hex_encode(input)
		output := result
		if output != expected: panic("incorrect output")
		checksum += output.byte_length() + 1

	return checksum

fn b64(input: Bytes, expected: String, count: Int, kind: String, limit: Int) Int:
	var checksum = 0

	for unused in 0..count:
		result := base64_encode(input)
		output := result
		if output != expected: panic("incorrect output")
		checksum += output.byte_length() + 1

	return checksum

fn unhex(input: String, expected: Bytes, count: Int, kind: String, limit: Int) Int:
	var checksum = 0

	for unused in 0..count:
		result := hex_decode(input, max_bytes: limit)

		if kind != "OK":
			if result.is_ok(): panic("unexpected success")

			err := result.err()
			message := if kind == "EINVAL": "encoding: invalid input" else: (
				if kind == "EOVERFLOW": "encoding: limit exceeded" else: "encoding: invalid data"
			)
			if err.kind != kind or err.message != message: panic("incorrect error")
			checksum += 1
			continue

		output := result.get()
		if output != expected: panic("incorrect output")
		checksum += output.length() + 1

	return checksum

fn utf16le(input: Bytes, expected: String, count: Int, kind: String, limit: Int) Int:
	var checksum = 0

	for unused in 0..count:
		result := utf16_decode(input, true, max_bytes: limit)

		if kind != "OK":
			if result.is_ok(): panic("unexpected success")

			err := result.err()
			message := if kind == "EINVAL": "encoding: invalid input" else: (
				if kind == "EOVERFLOW": "encoding: limit exceeded" else: "encoding: invalid data"
			)
			if err.kind != kind or err.message != message: panic("incorrect error")
			checksum += 1
			continue

		output := result.get()
		if output != expected: panic("incorrect output")
		checksum += output.byte_length() + 1

	return checksum

fn utf16be(input: Bytes, expected: String, count: Int, kind: String, limit: Int) Int:
	var checksum = 0

	for unused in 0..count:
		result := utf16_decode(input, false, max_bytes: limit)

		if kind != "OK":
			if result.is_ok(): panic("unexpected success")

			err := result.err()
			message := if kind == "EINVAL": "encoding: invalid input" else: (
				if kind == "EOVERFLOW": "encoding: limit exceeded" else: "encoding: invalid data"
			)
			if err.kind != kind or err.message != message: panic("incorrect error")
			checksum += 1
			continue

		output := result.get()
		if output != expected: panic("incorrect output")
		checksum += output.byte_length() + 1

	return checksum

fn run_hex(args: List[String]) Int:
	input := read_file(args[1]).wait().get()
	expected := read_file(args[2]).wait().get().decode_utf8().get()
	count := args[3].parse_int().get()
	kind := args[4]
	limit := args[5].parse_int().get()
	warm := if count / 10 > 0: count / 10 else: 1
	warm_sum := hex(input, expected, warm, kind, limit)
	start := monotonic()
	checksum := hex(input, expected, count, kind, limit)
	elapsed := monotonic().difference(start).to_nanoseconds()
	print("{count},{elapsed},{checksum},{warm_sum}")
	return 0

fn run_b64(args: List[String]) Int:
	input := read_file(args[1]).wait().get()
	expected := read_file(args[2]).wait().get().decode_utf8().get()
	count := args[3].parse_int().get()
	kind := args[4]
	limit := args[5].parse_int().get()
	warm := if count / 10 > 0: count / 10 else: 1
	warm_sum := b64(input, expected, warm, kind, limit)
	start := monotonic()
	checksum := b64(input, expected, count, kind, limit)
	elapsed := monotonic().difference(start).to_nanoseconds()
	print("{count},{elapsed},{checksum},{warm_sum}")
	return 0

fn run_unhex(args: List[String]) Int:
	input := read_file(args[1]).wait().get().decode_utf8().get()
	expected := read_file(args[2]).wait().get()
	count := args[3].parse_int().get()
	kind := args[4]
	limit := args[5].parse_int().get()
	warm := if count / 10 > 0: count / 10 else: 1
	warm_sum := unhex(input, expected, warm, kind, limit)
	start := monotonic()
	checksum := unhex(input, expected, count, kind, limit)
	elapsed := monotonic().difference(start).to_nanoseconds()
	print("{count},{elapsed},{checksum},{warm_sum}")
	return 0

fn run_utf16le(args: List[String]) Int:
	input := read_file(args[1]).wait().get()
	expected := read_file(args[2]).wait().get().decode_utf8().get()
	count := args[3].parse_int().get()
	kind := args[4]
	limit := args[5].parse_int().get()
	warm := if count / 10 > 0: count / 10 else: 1
	warm_sum := utf16le(input, expected, warm, kind, limit)
	start := monotonic()
	checksum := utf16le(input, expected, count, kind, limit)
	elapsed := monotonic().difference(start).to_nanoseconds()
	print("{count},{elapsed},{checksum},{warm_sum}")
	return 0

fn run_utf16be(args: List[String]) Int:
	input := read_file(args[1]).wait().get()
	expected := read_file(args[2]).wait().get().decode_utf8().get()
	count := args[3].parse_int().get()
	kind := args[4]
	limit := args[5].parse_int().get()
	warm := if count / 10 > 0: count / 10 else: 1
	warm_sum := utf16be(input, expected, warm, kind, limit)
	start := monotonic()
	checksum := utf16be(input, expected, count, kind, limit)
	elapsed := monotonic().difference(start).to_nanoseconds()
	print("{count},{elapsed},{checksum},{warm_sum}")
	return 0

export fn main() Int:
	args := arguments()

	match args[0]:
		"hex": return run_hex(args)
		"b64": return run_b64(args)
		"unhex": return run_unhex(args)
		"utf16le": return run_utf16le(args)
		"utf16be": return run_utf16be(args)
		_: return 2
