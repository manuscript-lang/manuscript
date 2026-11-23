import (
	Bytes, BytesBuilder from "@std/bytes.ms",
	base64_encode from "@std/data/encoding.ms",
	parse from "@std/data/json.ms",
	arguments from "@std/os/env.ms",
	monotonic from "@std/time.ms",
)

fn main() Int:
	args := arguments()
	length := args[0].parse_int().get()
	count := args[1].parse_int().get()
	rounds := args[2].parse_int().get()
	var bytes = BytesBuilder()
	for i in 0..length: bytes.append((i % 256).to_uint8().get())

	expected := bytes.build()
	encoded := base64_encode(expected)
	var json = ""
	json += "["

	for i in 0..count:
		if i > 0: json += ","
		json += f"\"{encoded}\""

	json += "]"

	text := json
	var checksum = 0
	start := monotonic()

	for i in 0..rounds:
		result := parse[List[Bytes]](text)
		if result.is_error(): return 2

		values := result.get()
		if values.length() != count: return 3

		for value in values:
			if value != expected: return 4

			checksum += value.length()

	elapsed := monotonic().difference(start).to_nanoseconds()
	print(f"{length} {count} {rounds} {checksum} {elapsed}")
	return 0
