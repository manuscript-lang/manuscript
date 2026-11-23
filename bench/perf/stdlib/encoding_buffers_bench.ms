import (
	Bytes, BytesBuilder from "@std/bytes.ms",
	Base32Options,
	ascii85_decode,
	ascii85_encode,
	base32_decode,
	base32_encode,
	base64_encode from "@std/data/encoding.ms",
	expect_equal from "@std/test/test.ms",
)

fn sample(length: Int, zero: Bool = false) Bytes:
	var out = BytesBuilder()

	for index in 0..length:
		value := if zero: 0 else: (index * 73 + 11) % 256
		out.append(value.to_uint8().get())

	return out.build()

// One prepared case: the input, the options and the answer the run must reproduce.
type Case:
	data: Bytes
	text: String
	expected_text: String
	expected: Bytes!
	hex: Bool
	padded: Bool
	url: Bool
	weight: Int
	limit: Int?

fn plain(data: Bytes) Case:
	return Case(
		data: data,
		text: "",
		expected_text: "",
		expected: ok(Bytes([])),
		limit: null,
		hex: false,
		padded: false,
		url: false,
		weight: 0,
	)

fn prep_unpadded(length: Int, url: Bool) Case:
	data := sample(length)
	expected := base64_encode(data, url).replace("=", "")
	var c = plain(data)
	c.url = url
	c.expected_text = expected
	return c

fn prep_base32(length: Int, hex: Bool, padded: Bool) Case:
	data := sample(length)
	options := Base32Options(hex_alphabet: hex, padded: padded)
	expected := base32_encode(data, options)
	expect_equal(base32_decode(expected, options).get(), data).get()

	var c = plain(data)
	c.hex = hex
	c.padded = padded
	c.expected_text = expected
	return c

fn prep_decode32(length: Int, hex: Bool, padded: Bool, mode: Int) Case:
	data := sample(length)
	var text = base32_encode(data, Base32Options(hex_alphabet: hex, padded: padded))
	if mode == 1 or mode == 7: text = "!" + ("A".repeat(text.length() - 1))
	if mode == 2: text = ("A".repeat(text.length() - 1)) + "!"

	var limit: Int? = null
	if mode == 3: limit = 0
	if mode == 4: limit = -1
	if mode == 5: limit = length
	if mode == 6 or mode == 7: limit = length * 2

	var expected: Bytes! = ok(data.clone())
	if mode == 1 or mode == 2 or mode == 7: expected = error(
		Error("encoding: invalid data", kind: "EBADMSG")
	)
	if mode == 3: expected = error(Error("encoding: limit exceeded", kind: "EOVERFLOW"))
	if mode == 4: expected = error(Error("encoding: invalid input", kind: "EINVAL"))

	var c = plain(data)
	c.hex = hex
	c.padded = padded
	c.text = text
	c.limit = limit
	c.expected = expected
	c.weight = if mode == 0 or mode == 5 or mode == 6: data.length() else: 1
	return c

fn prep_encode85(length: Int) Case:
	data := sample(length)
	expected := ascii85_encode(data)
	expect_equal(ascii85_decode(expected).get(), data).get()

	var c = plain(data)
	c.expected_text = expected
	return c

fn prep_decode85(
	length: Int,
	bounded: Bool,
	under: Bool,
	zero: Bool = false,
	bad: Int = 0,
) Case:
	data := sample(length, zero)
	var text = ascii85_encode(data)
	if bad == 1: text = "v" + text
	if bad == 2: text += "v"

	var limit: Int? = null
	if bounded: limit = if under: length - 1 else: length

	var expected: Bytes! = ok(data.clone())
	if under: expected = error(Error("encoding: limit exceeded", kind: "EOVERFLOW"))
	if bad != 0: expected = error(Error("encoding: invalid data", kind: "EBADMSG"))

	var c = plain(data)
	c.text = text
	c.limit = limit
	c.expected = expected
	c.weight = if bad == 0 and not under: data.length() else: 1
	return c

fn prep_zero_budget() Case:
	var c = plain(Bytes([]))
	c.text = ascii85_encode(sample(4096))
	c.limit = 0
	c.expected = error(Error("encoding: limit exceeded", kind: "EOVERFLOW"))
	c.weight = 1
	return c

fn prep_whitespace(bounded: Bool) Case:
	var c = plain(Bytes([]))
	c.text = " \t\r\n".repeat(16384)
	c.limit = if bounded: 0 else: null
	c.weight = 1
	return c

fn run_unpadded(c: Case) Int!:
	actual := base64_encode(c.data, c.url, false)
	expect_equal(actual, c.expected_text)?
	return ok(actual.length())

fn run_base32(c: Case) Int!:
	actual := base32_encode(
		c.data,
		Base32Options(hex_alphabet: c.hex, padded: c.padded),
	)
	expect_equal(actual, c.expected_text)?
	return ok(actual.length())

fn run_decode32(c: Case) Int!:
	actual := base32_decode(
		c.text,
		Base32Options(hex_alphabet: c.hex, padded: c.padded),
		c.limit,
	)
	expect_equal(actual, c.expected)?
	return ok(c.weight)

fn run_encode85(c: Case) Int!:
	actual := ascii85_encode(c.data)
	expect_equal(actual, c.expected_text)?
	return ok(actual.length())

fn run_decode85(c: Case) Int!:
	actual := ascii85_decode(c.text, c.limit)
	expect_equal(actual, c.expected)?
	return ok(c.weight)

type BenchData:
	cases: List[Case]

fn make_fixture() BenchData:
	var cases: List[Case] = []
	cases.append(prep_unpadded(0, false))
	cases.append(prep_unpadded(4, false))
	cases.append(prep_unpadded(7, false))
	cases.append(prep_unpadded(21, false))
	cases.append(prep_unpadded(4096, false))
	cases.append(prep_unpadded(1048576, false))
	cases.append(prep_unpadded(21, true))
	cases.append(prep_unpadded(4096, true))
	cases.append(prep_base32(21, false, true))
	cases.append(prep_base32(4096, false, false))
	cases.append(prep_base32(4096, true, true))
	cases.append(prep_base32(21, true, false))
	cases.append(prep_encode85(21))
	cases.append(prep_encode85(4096))
	cases.append(prep_decode85(0, false, false))
	cases.append(prep_decode85(0, true, false))
	cases.append(prep_decode85(8, false, false))
	cases.append(prep_decode85(8, true, false))
	cases.append(prep_decode85(4096, false, false))
	cases.append(prep_decode85(4096, true, false))
	cases.append(prep_decode85(8, true, true))
	cases.append(prep_decode85(4096, true, true))
	cases.append(prep_zero_budget())
	cases.append(prep_decode85(4096, true, false, bad: 1))
	cases.append(prep_decode85(4096, true, false, bad: 2))
	cases.append(prep_decode85(8, false, false, true))
	cases.append(prep_decode85(8, true, false, true))
	cases.append(prep_decode85(8, true, true, true))
	cases.append(prep_whitespace(false))
	cases.append(prep_whitespace(true))
	cases.append(prep_decode32(7, false, true, 0))
	cases.append(prep_decode32(4096, false, true, 0))
	cases.append(prep_decode32(4096, false, true, 5))
	cases.append(prep_decode32(4096, false, true, 6))
	cases.append(prep_decode32(4096, false, true, 1))
	cases.append(prep_decode32(1048576, false, true, 1))
	cases.append(prep_decode32(4096, false, true, 7))
	cases.append(prep_decode32(4096, false, true, 2))
	cases.append(prep_decode32(4096, false, true, 3))
	cases.append(prep_decode32(4096, false, true, 4))
	cases.append(prep_decode32(7, true, false, 0))
	cases.append(prep_decode32(4096, true, false, 0))
	cases.append(prep_decode32(4096, true, false, 5))
	cases.append(prep_decode32(4096, true, false, 6))
	cases.append(prep_decode32(4096, true, false, 1))
	cases.append(prep_decode32(1048576, true, false, 1))
	cases.append(prep_decode32(4096, true, false, 7))
	cases.append(prep_decode32(4096, true, false, 2))
	cases.append(prep_decode32(4096, true, false, 3))
	cases.append(prep_decode32(4096, true, false, 4))
	return BenchData(cases: cases)

bench "buffers.unpadded.std.0":
	run_unpadded(fixture.cases[0])?

bench "buffers.unpadded.std.4":
	run_unpadded(fixture.cases[1])?

bench "buffers.unpadded.std.7":
	run_unpadded(fixture.cases[2])?

bench "buffers.unpadded.std.21":
	run_unpadded(fixture.cases[3])?

bench "buffers.unpadded.std.4096":
	run_unpadded(fixture.cases[4])?

bench "buffers.unpadded.std.1048576":
	run_unpadded(fixture.cases[5])?

bench "buffers.unpadded.url.21":
	run_unpadded(fixture.cases[6])?

bench "buffers.unpadded.url.4096":
	run_unpadded(fixture.cases[7])?

bench "buffers.base32.std.pad.21":
	run_base32(fixture.cases[8])?

bench "buffers.base32.std.raw.4096":
	run_base32(fixture.cases[9])?

bench "buffers.base32.hex.pad.4096":
	run_base32(fixture.cases[10])?

bench "buffers.base32.hex.raw.21":
	run_base32(fixture.cases[11])?

bench "buffers.ascii85.encode.21":
	run_encode85(fixture.cases[12])?

bench "buffers.ascii85.encode.4096":
	run_encode85(fixture.cases[13])?

bench "buffers.ascii85.none.0":
	run_decode85(fixture.cases[14])?

bench "buffers.ascii85.exact.0":
	run_decode85(fixture.cases[15])?

bench "buffers.ascii85.none.8":
	run_decode85(fixture.cases[16])?

bench "buffers.ascii85.exact.8":
	run_decode85(fixture.cases[17])?

bench "buffers.ascii85.none.4096":
	run_decode85(fixture.cases[18])?

bench "buffers.ascii85.exact.4096":
	run_decode85(fixture.cases[19])?

bench "buffers.ascii85.under.8":
	run_decode85(fixture.cases[20])?

bench "buffers.ascii85.under.4096":
	run_decode85(fixture.cases[21])?

bench "buffers.ascii85.zero.4096":
	run_decode85(fixture.cases[22])?

bench "buffers.ascii85.invalid.first":
	run_decode85(fixture.cases[23])?

bench "buffers.ascii85.invalid.last":
	run_decode85(fixture.cases[24])?

bench "buffers.ascii85.z.none":
	run_decode85(fixture.cases[25])?

bench "buffers.ascii85.z.exact":
	run_decode85(fixture.cases[26])?

bench "buffers.ascii85.z.under":
	run_decode85(fixture.cases[27])?

bench "buffers.ascii85.whitespace.none":
	run_decode85(fixture.cases[28])?

bench "buffers.ascii85.whitespace.exact":
	run_decode85(fixture.cases[29])?

bench "buffers.decode32.std.pad.valid.7":
	run_decode32(fixture.cases[30])?

bench "buffers.decode32.std.pad.valid.4096":
	run_decode32(fixture.cases[31])?

bench "buffers.decode32.std.pad.exact.4096":
	run_decode32(fixture.cases[32])?

bench "buffers.decode32.std.pad.generous.4096":
	run_decode32(fixture.cases[33])?

bench "buffers.decode32.std.pad.first.4096":
	run_decode32(fixture.cases[34])?

bench "buffers.decode32.std.pad.first.1048576":
	run_decode32(fixture.cases[35])?

bench "buffers.decode32.std.pad.first.generous.4096":
	run_decode32(fixture.cases[36])?

bench "buffers.decode32.std.pad.last.4096":
	run_decode32(fixture.cases[37])?

bench "buffers.decode32.std.pad.zero.4096":
	run_decode32(fixture.cases[38])?

bench "buffers.decode32.std.pad.negative.4096":
	run_decode32(fixture.cases[39])?

bench "buffers.decode32.hex.raw.valid.7":
	run_decode32(fixture.cases[40])?

bench "buffers.decode32.hex.raw.valid.4096":
	run_decode32(fixture.cases[41])?

bench "buffers.decode32.hex.raw.exact.4096":
	run_decode32(fixture.cases[42])?

bench "buffers.decode32.hex.raw.generous.4096":
	run_decode32(fixture.cases[43])?

bench "buffers.decode32.hex.raw.first.4096":
	run_decode32(fixture.cases[44])?

bench "buffers.decode32.hex.raw.first.1048576":
	run_decode32(fixture.cases[45])?

bench "buffers.decode32.hex.raw.first.generous.4096":
	run_decode32(fixture.cases[46])?

bench "buffers.decode32.hex.raw.last.4096":
	run_decode32(fixture.cases[47])?

bench "buffers.decode32.hex.raw.zero.4096":
	run_decode32(fixture.cases[48])?

bench "buffers.decode32.hex.raw.negative.4096":
	run_decode32(fixture.cases[49])?
