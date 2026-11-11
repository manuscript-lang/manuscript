import (
	Bytes from "@std/bytes.ms",
	expect_equal from "@std/test/test.ms",
)

test "index_of_byte finds a byte at or after start":
	data := Bytes([1, 2, 3, 2, 255])
	expect_equal(data.index_of_byte(2, 0), 1)?
	expect_equal(data.index_of_byte(2, 2), 3)?
	expect_equal(data.index_of_byte(255, 0), 4)?
	expect_equal(data.index_of_byte(9, 0), none)?

test "index_of_byte handles out-of-range arguments":
	data := Bytes([1, 2])
	expect_equal(data.index_of_byte(1, -3), 0)?
	expect_equal(data.index_of_byte(1, 5), none)?
	expect_equal(data.index_of_byte(2, 2), none)?
	expect_equal(Bytes([]).index_of_byte(0, 0), none)?

test "decode_utf8_range decodes a byte range":
	data := "aé€b".to_bytes()
	expect_equal(data.decode_utf8_range(0, data.length()), "aé€b")?
	expect_equal(data.decode_utf8_range(1, 3), "é")?
	expect_equal(data.decode_utf8_range(2, 3), none)?
	expect_equal(data.decode_utf8_range(2, 2), "")?

test "view borrows a range without copying":
	data := Bytes([1, 2, 3, 4, 5])
	middle := data.view(1, 4)
	expect_equal(middle.length(), 3)?
	expect_equal(middle.get(0, none), 2)?
	expect_equal(data.view(-2, 5).clone(), Bytes([4, 5]))?
	expect_equal(data.view(2, 2).length(), 0)?

	kept := middle.clone()
	expect_equal(kept, Bytes([2, 3, 4]))?

test "view of a temporary is owned":
	tail := "hello".to_bytes().view(1, 5)
	expect_equal(tail, "ello".to_bytes())?
