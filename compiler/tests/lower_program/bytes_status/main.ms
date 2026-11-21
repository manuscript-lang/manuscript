import hex_decode from "@std/data/encoding.ms"

fn main() Int:
	if hex_decode("0102", none).is_ok(): return 1
	return 0
