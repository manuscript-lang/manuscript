import (
	Bytes, BytesBuilder from "@std/bytes.ms",
	ascii_decode,
	base64_encode,
	hex_decode,
	hex_encode,
	utf16_decode from "@std/data/encoding.ms",
	Utf8Error, Utf8Scalar, decode_first, decode_last from "@std/data/utf8.ms",
	keep, measure from "@std/test/bench.ms",
	expect_equal from "@std/test/test.ms",
)

fn zeros(count: Int) Bytes:
	var out = BytesBuilder()
	for unused in 0..count: out.append(0)
	return out.build()

fn decode_case(length: Int, limit: Int?, bad: Int = 0) Unit!:
	var text = "0".repeat(length)?
	if bad == 1: text = "z" + text.drop(1)
	if bad == 2: text = text.take(length - 1) + "z"

	maximum := limit.get(9223372036854775807)
	var expected: Bytes! = ok(Bytes([]))

	if maximum < 0:
		expected = error(Error("encoding: invalid input", kind: "EINVAL"))
	else if length / 2 > maximum:
		expected = error(Error("encoding: limit exceeded", kind: "EOVERFLOW"))
	else if length % 2 != 0 or bad != 0:
		expected = error(Error("encoding: invalid data", kind: "EBADMSG"))
	else:
		expected = ok(zeros(length / 2))

	fn work() Unit!:
		expect_equal(hex_decode(text, limit), expected)?
		return keep(length)

	measure(1, work)?

fn unicode_case(limit: Int) Unit!:
	expected: Bytes! := error(
		Error(
			if limit == 0: "encoding: limit exceeded" else: "encoding: invalid data",
			kind: if limit == 0: "EOVERFLOW" else: "EBADMSG"
		)
	)

	fn work() Unit!:
		expect_equal(hex_decode("é", limit), expected)?
		return keep(2)

	measure(1, work)?

fn neighbor(which: Int) Unit!:
	data := zeros(if which == 3 or which == 4: 8192 else: 4096)
	text := "\u{0}".repeat(4096)?
	expected_text: String! := ok(text.clone())
	hex := "00".repeat(4096)?
	b64 := ("A".repeat(5462)?) + "=="
	scalar := "é".to_bytes()

	fn work() Unit!:
		if which == 0: expect_equal(hex_encode(data), hex)?
		else if which == 1: expect_equal(base64_encode(data, false), b64)?
		else if which == 2: expect_equal(ascii_decode(data), expected_text)?
		else if which == 3: expect_equal(utf16_decode(data, true, 4096), expected_text)?
		else if which == 4: expect_equal(utf16_decode(data, false, 4096), expected_text)?
		else if which == 5: expect_equal(
			decode_first(scalar, 0), ok(Utf8Scalar(233, 2))
		)?
		else: expect_equal(decode_last(scalar, 2), ok(Utf8Scalar(233, 2)))?

		return keep(4096)

	measure(1, work)?

bench "hex.limit.empty.none":
	decode_case(0, none, 0)?

bench "hex.limit.empty.zero":
	decode_case(0, 0, 0)?

bench "hex.limit.empty.negative":
	decode_case(0, -1, 0)?

bench "hex.limit.one.odd":
	decode_case(1, 0, 0)?

bench "hex.limit.tiny.zero":
	decode_case(2, 0, 0)?

bench "hex.limit.tiny.exact":
	decode_case(2, 1, 0)?

bench "hex.limit.tiny.none":
	decode_case(2, none, 0)?

bench "hex.limit.tiny.odd.over":
	decode_case(3, 0, 0)?

bench "hex.limit.tiny.bad.limit":
	decode_case(2, 0, 1)?

bench "hex.limit.tiny.bad.fit":
	decode_case(2, 1, 1)?

bench "hex.limit.zero.8192":
	decode_case(8192, 0, 0)?

bench "hex.limit.under.8192":
	decode_case(8192, 4095, 0)?

bench "hex.limit.exact.8192":
	decode_case(8192, 4096, 0)?

bench "hex.limit.none.8192":
	decode_case(8192, none, 0)?

bench "hex.limit.negative.8192":
	decode_case(8192, -1, 0)?

bench "hex.limit.bad.first.8192":
	decode_case(8192, none, 1)?

bench "hex.limit.bad.last.8192":
	decode_case(8192, none, 2)?

bench "hex.limit.odd.fit.8192":
	decode_case(8193, 4096, 0)?

bench "hex.limit.odd.under.8192":
	decode_case(8193, 4095, 0)?

bench "hex.limit.zero.1048576":
	decode_case(1048576, 0, 0)?

bench "hex.limit.under.1048576":
	decode_case(1048576, 524287, 0)?

bench "hex.limit.exact.1048576":
	decode_case(1048576, 524288, 0)?

bench "hex.limit.none.1048576":
	decode_case(1048576, none, 0)?

bench "hex.limit.negative.1048576":
	decode_case(1048576, -1, 0)?

bench "hex.limit.bad.first.1048576":
	decode_case(1048576, none, 1)?

bench "hex.limit.bad.last.1048576":
	decode_case(1048576, none, 2)?

bench "hex.limit.odd.fit.1048576":
	decode_case(1048577, 524288, 0)?

bench "hex.limit.odd.under.1048576":
	decode_case(1048577, 524287, 0)?

bench "hex.limit.unicode.0":
	unicode_case(0)?

bench "hex.limit.unicode.1":
	unicode_case(1)?

bench "hex.neighbor.hex.encode":
	neighbor(0)?

bench "hex.neighbor.base64.encode":
	neighbor(1)?

bench "hex.neighbor.ascii.decode":
	neighbor(2)?

bench "hex.neighbor.utf16.le":
	neighbor(3)?

bench "hex.neighbor.utf16.be":
	neighbor(4)?

bench "hex.neighbor.utf8.first":
	neighbor(5)?

bench "hex.neighbor.utf8.last":
	neighbor(6)?
