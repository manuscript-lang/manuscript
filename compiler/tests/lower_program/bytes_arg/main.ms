import (
	Bytes from "@std/bytes.ms",
	hex_encode from "@std/data/encoding.ms",
)

fn main() Int:
	if hex_encode(Bytes([1, 2])).length() == 4: return 1
	return 0
