import (
	expect_equal from "@std/test/test.ms",

	parse_total from "./shapes.ms",
)

fn main() Int {
	total := parse_total(["3", "4", "x"])
	print(f"total {total}")
	return 0
}

test "main total" {
	expect_equal(parse_total(["1", "2"]), 3)?
}
