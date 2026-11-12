// conform: tags=testing,tier-stdlib
// conform: phase=test
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

test "hex encoding covers every byte and empty nested views":
	var values = List[UInt8]()
	for value in 0..256:
		values.append(value.to_uint8().get(0))

	data := Bytes(values)
	expected := "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f404142434445464748494a4b4c4d4e4f505152535455565758595a5b5c5d5e5f606162636465666768696a6b6c6d6e6f707172737475767778797a7b7c7d7e7f808182838485868788898a8b8c8d8e8f909192939495969798999a9b9c9d9e9fa0a1a2a3a4a5a6a7a8a9aaabacadaeafb0b1b2b3b4b5b6b7b8b9babbbcbdbebfc0c1c2c3c4c5c6c7c8c9cacbcccdcecfd0d1d2d3d4d5d6d7d8d9dadbdcdddedfe0e1e2e3e4e5e6e7e8e9eaebecedeeeff0f1f2f3f4f5f6f7f8f9fafbfcfdfeff"
	expect_equal(hex_encode(data), expected)?
	expect_equal(hex_decode(expected).get(), data)?

	outer := data.view(17, 240)
	empty := outer.view(13, 13)
	expect_equal(hex_encode(empty), "")?

test "hex encoding preserves output across bounded chunks":
	for length in [8191, 8192, 8193, 16383, 16384, 16385]:
		text := "x".repeat(length)?
		storage := ("!" + text + "?").to_bytes()
		data := storage.view(1, length + 1)
		expect_equal(hex_encode(data), "78".repeat(length)?)?
