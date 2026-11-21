import (
	divide_wide, remainder_wide from "@std/math/math.ms",
	parse_timestamp from "@std/time.ms",
)

fn main() Void:
	print(parse_timestamp("2026-01-01T00:00:00Z").is_ok())
	print(divide_wide(0, 7, 2).is_ok())
	print(remainder_wide(0, 7, 2).is_ok())
