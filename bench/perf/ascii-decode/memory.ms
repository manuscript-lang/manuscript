import (
	ascii_decode from "@std/data/encoding.ms",
	expect_equal from "@std/test/test.ms",
)

fn work() Unit!:
	expected := "A".repeat(1048576)?
	data := expected.to_bytes()
	var checksum = 0
	for unused in 0..32:
		checksum += (ascii_decode(data)?).byte_length()
	expect_equal(checksum, 33554432)?

fn main() Unit:
	work().get()
