import (
	parse_float, parse_int from "@std/math/math.ms",
	rename from "@std/os/fs.ms",
)

fn main() Int:
	n := parse_int("12")
	if n.is_ok(): return 1

	f := parse_float("2.5")
	if f.is_ok(): return 2

	moved := rename("a", "b")
	if moved.is_ok(): return 3

	return 0
