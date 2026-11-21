import parse_big_int from "@std/math/math.ms"

fn digits(text: String, limit: Int?) Int:
	if parse_big_int(text, 10, limit).is_ok(): return 1
	return 0

fn main() Int:
	return digits("12", none)
