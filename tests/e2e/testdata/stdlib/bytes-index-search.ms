import (
	Bytes from "@std/bytes.ms",
	expect_equal from "@std/test/test.ms",
)

test "byte search preserves offsets across scanner boundaries":
	needles: List[UInt8] := [0, 1, 128, 255]

	for value in needles:
		for size in [0, 1, 7, 8, 15, 16, 31, 32, 33, 63, 64, 65, 127, 128, 129]:
			empty_hits := "a".repeat(size).get().to_bytes()
			expect_equal(empty_hits.index_of_byte(value, 0), none)?

			for at in 0..size:
				data := empty_hits.with_value(at, value)
				expect_equal(data.index_of_byte(value, -1), at)?
				expect_equal(data.index_of_byte(value, at), at)?
				if at >= 17: expect_equal(data.index_of_byte(value, 1), at)?
				expect_equal(data.index_of_byte(value, at + 1), none)?
				expect_equal(data.index_of_byte(value, size), none)?
				expect_equal(data.index_of_byte(value, size + 1), none)?

test "byte search returns the earliest hit at or after start":
	data := Bytes([255, 0, 255, 128, 255])
	expect_equal(data.index_of_byte(255, 0), 0)?
	expect_equal(data.index_of_byte(255, 1), 2)?
	expect_equal(data.index_of_byte(255, 3), 4)?
	expect_equal(data.index_of_byte(255, -9223372036854775807 - 1), 0)?
	expect_equal(data.index_of_byte(255, 9223372036854775807), none)?
