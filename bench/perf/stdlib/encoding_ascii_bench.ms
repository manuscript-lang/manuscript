import (
	Bytes from "@std/bytes.ms",
	ascii_decode from "@std/data/encoding.ms",
	keep, measure from "@std/test/bench.ms",
	expect_equal from "@std/test/test.ms",
)

bench "ascii.valid.0":
	expected := "Az09 \n\u{0}".repeat(0)?
	data := expected.to_bytes()
	expect_equal(data.length(), 0)?
	expect_equal(ascii_decode(data)?, expected)?
	measure(1, fn: keep((ascii_decode(data)?).byte_length()))?

bench "ascii.valid.7":
	expected := "Az09 \n\u{0}".repeat(1)?
	data := expected.to_bytes()
	expect_equal(data.length(), 7)?
	expect_equal(ascii_decode(data)?, expected)?
	measure(1, fn: keep((ascii_decode(data)?).byte_length()))?

bench "ascii.valid.56":
	expected := "Az09 \n\u{0}".repeat(8)?
	data := expected.to_bytes()
	expect_equal(data.length(), 56)?
	expect_equal(ascii_decode(data)?, expected)?
	measure(1, fn: keep((ascii_decode(data)?).byte_length()))?

bench "ascii.valid.4095":
	expected := "Az09 \n\u{0}".repeat(585)?
	data := expected.to_bytes()
	expect_equal(data.length(), 4095)?
	expect_equal(ascii_decode(data)?, expected)?
	measure(1, fn: keep((ascii_decode(data)?).byte_length()))?

bench "ascii.valid.1048579":
	expected := "Az09 \n\u{0}".repeat(149797)?
	data := expected.to_bytes()
	expect_equal(data.length(), 1048579)?
	expect_equal(ascii_decode(data)?, expected)?
	measure(1, fn: keep((ascii_decode(data)?).byte_length()))?

bench "ascii.invalid.first.1":
	good := ("Az09 \n\u{0}".repeat(0)?).to_bytes()
	bad := Bytes([255])
	data := bad.concat(good)
	expect_equal(data.length(), 1)?

	expected: String! := error(Error("encoding: invalid data", kind: "EBADMSG"))
	expect_equal(ascii_decode(data), expected)?

	fn work() Unit!:
		actual := ascii_decode(data)
		expect_equal(actual, expected)?
		return keep(data.length())

	measure(1, work)?

bench "ascii.invalid.last.1":
	good := ("Az09 \n\u{0}".repeat(0)?).to_bytes()
	bad := Bytes([255])
	data := good.concat(bad)
	expect_equal(data.length(), 1)?

	expected: String! := error(Error("encoding: invalid data", kind: "EBADMSG"))
	expect_equal(ascii_decode(data), expected)?

	fn work() Unit!:
		actual := ascii_decode(data)
		expect_equal(actual, expected)?
		return keep(data.length())

	measure(1, work)?

bench "ascii.invalid.first.57":
	good := ("Az09 \n\u{0}".repeat(8)?).to_bytes()
	bad := Bytes([255])
	data := bad.concat(good)
	expect_equal(data.length(), 57)?

	expected: String! := error(Error("encoding: invalid data", kind: "EBADMSG"))
	expect_equal(ascii_decode(data), expected)?

	fn work() Unit!:
		actual := ascii_decode(data)
		expect_equal(actual, expected)?
		return keep(data.length())

	measure(1, work)?

bench "ascii.invalid.last.57":
	good := ("Az09 \n\u{0}".repeat(8)?).to_bytes()
	bad := Bytes([255])
	data := good.concat(bad)
	expect_equal(data.length(), 57)?

	expected: String! := error(Error("encoding: invalid data", kind: "EBADMSG"))
	expect_equal(ascii_decode(data), expected)?

	fn work() Unit!:
		actual := ascii_decode(data)
		expect_equal(actual, expected)?
		return keep(data.length())

	measure(1, work)?

bench "ascii.invalid.first.4096":
	good := ("Az09 \n\u{0}".repeat(585)?).to_bytes()
	bad := Bytes([255])
	data := bad.concat(good)
	expect_equal(data.length(), 4096)?

	expected: String! := error(Error("encoding: invalid data", kind: "EBADMSG"))
	expect_equal(ascii_decode(data), expected)?

	fn work() Unit!:
		actual := ascii_decode(data)
		expect_equal(actual, expected)?
		return keep(data.length())

	measure(1, work)?

bench "ascii.invalid.last.4096":
	good := ("Az09 \n\u{0}".repeat(585)?).to_bytes()
	bad := Bytes([255])
	data := good.concat(bad)
	expect_equal(data.length(), 4096)?

	expected: String! := error(Error("encoding: invalid data", kind: "EBADMSG"))
	expect_equal(ascii_decode(data), expected)?

	fn work() Unit!:
		actual := ascii_decode(data)
		expect_equal(actual, expected)?
		return keep(data.length())

	measure(1, work)?

bench "ascii.invalid.first.1048580":
	good := ("Az09 \n\u{0}".repeat(149797)?).to_bytes()
	bad := Bytes([255])
	data := bad.concat(good)
	expect_equal(data.length(), 1048580)?

	expected: String! := error(Error("encoding: invalid data", kind: "EBADMSG"))
	expect_equal(ascii_decode(data), expected)?

	fn work() Unit!:
		actual := ascii_decode(data)
		expect_equal(actual, expected)?
		return keep(data.length())

	measure(1, work)?

bench "ascii.invalid.last.1048580":
	good := ("Az09 \n\u{0}".repeat(149797)?).to_bytes()
	bad := Bytes([255])
	data := good.concat(bad)
	expect_equal(data.length(), 1048580)?

	expected: String! := error(Error("encoding: invalid data", kind: "EBADMSG"))
	expect_equal(ascii_decode(data), expected)?

	fn work() Unit!:
		actual := ascii_decode(data)
		expect_equal(actual, expected)?
		return keep(data.length())

	measure(1, work)?

bench "ascii.unicode.accent.1":
	data := ("é".repeat(1)?).to_bytes()
	expected: String! := error(Error("encoding: invalid data", kind: "EBADMSG"))
	expect_equal(ascii_decode(data), expected)?

	fn work() Unit!:
		expect_equal(ascii_decode(data), expected)?
		return keep(data.length())

	measure(1, work)?

bench "ascii.unicode.emoji.1":
	data := ("🙂".repeat(1)?).to_bytes()
	expected: String! := error(Error("encoding: invalid data", kind: "EBADMSG"))
	expect_equal(ascii_decode(data), expected)?

	fn work() Unit!:
		expect_equal(ascii_decode(data), expected)?
		return keep(data.length())

	measure(1, work)?

bench "ascii.unicode.accent.2048":
	data := ("é".repeat(2048)?).to_bytes()
	expected: String! := error(Error("encoding: invalid data", kind: "EBADMSG"))
	expect_equal(ascii_decode(data), expected)?

	fn work() Unit!:
		expect_equal(ascii_decode(data), expected)?
		return keep(data.length())

	measure(1, work)?

bench "ascii.unicode.emoji.2048":
	data := ("🙂".repeat(2048)?).to_bytes()
	expected: String! := error(Error("encoding: invalid data", kind: "EBADMSG"))
	expect_equal(ascii_decode(data), expected)?

	fn work() Unit!:
		expect_equal(ascii_decode(data), expected)?
		return keep(data.length())

	measure(1, work)?

bench "ascii.unicode.accent.524288":
	data := ("é".repeat(524288)?).to_bytes()
	expected: String! := error(Error("encoding: invalid data", kind: "EBADMSG"))
	expect_equal(ascii_decode(data), expected)?

	fn work() Unit!:
		expect_equal(ascii_decode(data), expected)?
		return keep(data.length())

	measure(1, work)?

bench "ascii.unicode.emoji.524288":
	data := ("🙂".repeat(524288)?).to_bytes()
	expected: String! := error(Error("encoding: invalid data", kind: "EBADMSG"))
	expect_equal(ascii_decode(data), expected)?

	fn work() Unit!:
		expect_equal(ascii_decode(data), expected)?
		return keep(data.length())

	measure(1, work)?

bench "ascii.unicode.first.8":
	tail := "A".repeat(8)?
	data := ("é" + tail).to_bytes()
	expect_equal(data.length(), 10)?

	expected: String! := error(Error("encoding: invalid data", kind: "EBADMSG"))
	expect_equal(ascii_decode(data), expected)?

	fn work() Unit!:
		expect_equal(ascii_decode(data), expected)?
		return keep(data.length())

	measure(1, work)?

bench "ascii.unicode.last.8":
	tail := "A".repeat(8)?
	data := (tail + "é").to_bytes()
	expect_equal(data.length(), 10)?

	expected: String! := error(Error("encoding: invalid data", kind: "EBADMSG"))
	expect_equal(ascii_decode(data), expected)?

	fn work() Unit!:
		expect_equal(ascii_decode(data), expected)?
		return keep(data.length())

	measure(1, work)?

bench "ascii.unicode.first.524288":
	tail := "A".repeat(524288)?
	data := ("é" + tail).to_bytes()
	expect_equal(data.length(), 524290)?

	expected: String! := error(Error("encoding: invalid data", kind: "EBADMSG"))
	expect_equal(ascii_decode(data), expected)?

	fn work() Unit!:
		expect_equal(ascii_decode(data), expected)?
		return keep(data.length())

	measure(1, work)?

bench "ascii.unicode.last.524288":
	tail := "A".repeat(524288)?
	data := (tail + "é").to_bytes()
	expect_equal(data.length(), 524290)?

	expected: String! := error(Error("encoding: invalid data", kind: "EBADMSG"))
	expect_equal(ascii_decode(data), expected)?

	fn work() Unit!:
		expect_equal(ascii_decode(data), expected)?
		return keep(data.length())

	measure(1, work)?
