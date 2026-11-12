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

export fn main() Int:
	args := arguments()
	op := args[0]
	input := read_file(args[1]).wait().get()
	expected := read_file(args[2]).wait().get()
	count := args[3].parse_int().get()
	kind := args[4]
	limit := args[5].parse_int().get()
	warm := if count / 10 > 0: count / 10 else: 1

	if op == "hex":
		data := input
		want := expected.decode_utf8().get()
		warm_sum := hex(data, want, warm, kind, limit)
		start := monotonic()
		checksum := hex(data, want, count, kind, limit)
		elapsed := monotonic().difference(start).to_nanoseconds()
		print("{count},{elapsed},{checksum},{warm_sum}")
		return 0

	if op == "b64":
		data := input
		want := expected.decode_utf8().get()
		warm_sum := b64(data, want, warm, kind, limit)
		start := monotonic()
		checksum := b64(data, want, count, kind, limit)
		elapsed := monotonic().difference(start).to_nanoseconds()
		print("{count},{elapsed},{checksum},{warm_sum}")
		return 0

	if op == "unhex":
		data := input.decode_utf8().get()
		want := expected
		warm_sum := unhex(data, want, warm, kind, limit)
		start := monotonic()
		checksum := unhex(data, want, count, kind, limit)
		elapsed := monotonic().difference(start).to_nanoseconds()
		print("{count},{elapsed},{checksum},{warm_sum}")
		return 0

	if op == "utf16le":
		data := input
		want := expected.decode_utf8().get()
		warm_sum := utf16le(data, want, warm, kind, limit)
		start := monotonic()
		checksum := utf16le(data, want, count, kind, limit)
		elapsed := monotonic().difference(start).to_nanoseconds()
		print("{count},{elapsed},{checksum},{warm_sum}")
		return 0

	if op == "utf16be":
		data := input
		want := expected.decode_utf8().get()
		warm_sum := utf16be(data, want, warm, kind, limit)
		start := monotonic()
		checksum := utf16be(data, want, count, kind, limit)
		elapsed := monotonic().difference(start).to_nanoseconds()
		print("{count},{elapsed},{checksum},{warm_sum}")
		return 0

	return 2
