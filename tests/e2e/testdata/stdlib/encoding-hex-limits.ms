import (
	Bytes from "@std/bytes.ms",
	hex_decode, hex_encode from "@std/data/encoding.ms",
	expect_equal from "@std/test/test.ms",
)

test "hex preflight preserves byte lengths and error precedence":
	invalid: Bytes! := error(Error("encoding: invalid data", kind: "EBADMSG"))
	negative: Bytes! := error(Error("encoding: invalid input", kind: "EINVAL"))
	limited: Bytes! := error(Error("encoding: limit exceeded", kind: "EOVERFLOW"))
	for text in ["", "a", "aaa", "zz", "é", "éa"]:
		expect_equal(hex_decode(text, -1), negative)?
	for text in ["aaa", "zz", "é", "éa"]:
		expect_equal(hex_decode(text, 0), limited)?
	for text in ["a", "zz", "é", "éa"]:
		expect_equal(hex_decode(text, 1), invalid)?
	expect_equal(hex_decode("a", 0), invalid)?
	expect_equal(hex_decode("", 0), ok(Bytes([])))?
	expect_equal(hex_decode("00fF", 2), ok(Bytes([0, 255])))?
	expect_equal(hex_decode("00fF", none), ok(Bytes([0, 255])))?

test "hex limits and round trips preserve actual nested byte views":
	storage := Bytes([255, 254, 0, 15, 16, 127, 128, 253])
	outer := storage.view(1, 8)
	data := outer.view(1, 6)
	text := hex_encode(data)
	expect_equal(text, "000f107f80")?
	expect_equal(hex_decode(text, 5), ok(Bytes([0, 15, 16, 127, 128])))?

	limited: Bytes! := error(Error("encoding: limit exceeded", kind: "EOVERFLOW"))
	expect_equal(hex_decode(text, 4), limited)?

test "hex rejects large over budget and odd inputs before digit validation":
	text := "00".repeat(524288).get()
	limited: Bytes! := error(Error("encoding: limit exceeded", kind: "EOVERFLOW"))
	invalid: Bytes! := error(Error("encoding: invalid data", kind: "EBADMSG"))
	expect_equal(hex_decode(text, 0), limited)?
	expect_equal(hex_decode(text + "z", 524287), limited)?
	expect_equal(hex_decode(text + "z", 524288), invalid)?
