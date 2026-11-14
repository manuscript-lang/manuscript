// conform: tags=testing,bytes,tier-stdlib
// conform: phase=test
import (
	Bytes from "@std/bytes.ms",
	BytesBuilder from "@std/bytes.ms",
	expect_equal from "@std/test/test.ms",
)

fn build(n: Int) Bytes:
	var b = BytesBuilder()
	var i = 0
	while i < n:
		b.append((i % 251).to_uint8().get(0))
		i += 1
	return b.build()

test "appends across capacity growth keep every byte":
	data := build(1000)
	expect_equal(data.length(), 1000)?
	expect_equal(data[0].to_int(), 0)?
	expect_equal(data[250].to_int(), 250)?
	expect_equal(data[251].to_int(), 0)?
	expect_equal(data[999].to_int(), 999 % 251)?

test "an empty builder builds empty bytes":
	expect_equal(build(0).length(), 0)?
