import (
	Bytes, BytesBuilder from "@std/bytes.ms",
	ascii_decode,
	base64_encode,
	hex_decode,
	hex_encode,
	utf16_decode from "@std/data/encoding.ms",
	Utf8Error, Utf8Scalar, decode_first, decode_last from "@std/data/utf8.ms",
	expect_equal from "@std/test/test.ms",
)

fn zeros(count Int) Bytes {
	var out = BytesBuilder()
	for unused in 0..count { out.append(0) }
	return out.build()
}

// One prepared case: the input, the limit and the answer the run must reproduce.
type Case {
	text String
	data, scalar Bytes
	expected Bytes!
	expected_text String!
	weight, which Int
	limit Int?
}

fn plain() Case {
	return Case(
		text: "",
		data: Bytes([]),
		scalar: Bytes([]),
		expected: ok(Bytes([])),
		expected_text: ok(""),
		weight: 0,
		which: 0,
	)
}

fn prep_decode(length Int, limit Int?, bad Int = 0) Case {
	var text = "0".repeat(length)
	if bad == 1 {
		text = "z" + text.view(1, text.length())
	}
	if bad == 2 {
		text = text.view(0, length - 1) + "z"
	}

	maximum := limit or 9223372036854775807
	var expected Bytes! = ok(Bytes([]))

	if maximum < 0 {
		expected = error(Error("encoding: invalid input", kind: "EINVAL"))
	} else if length / 2 > maximum {
		expected = error(Error("encoding: limit exceeded", kind: "EOVERFLOW"))
	} else if length % 2 != 0 or bad != 0 {
		expected = error(Error("encoding: invalid data", kind: "EBADMSG"))
	} else {
		expected = ok(zeros(length / 2))
	}

	var c = plain()
	c.text = text
	c.limit = limit
	c.expected = expected
	c.weight = length
	return c
}

fn prep_unicode(limit Int) Case {
	var c = plain()
	c.text = "é"
	c.limit = limit
	c.expected = error(
		Error(
			if limit == 0 { "encoding: limit exceeded" } else { "encoding: invalid data" },
			kind: if limit == 0 { "EOVERFLOW" } else { "EBADMSG" },
		)
	)
	c.weight = 2
	return c
}

fn prep_neighbor(which Int) Case {
	text := "\u{0}".repeat(4096)
	var c = plain()
	c.data = zeros(if which == 3 or which == 4 { 8192 } else { 4096 })
	c.expected_text = ok(text.clone())
	c.text = if which == 0 { "00".repeat(4096) } else { ("A".repeat(5462)) + "==" }
	c.scalar = "é".to_bytes()
	c.which = which
	c.weight = 4096
	return c
}

fn run_decode(c Case) Int! {
	expect_equal(hex_decode(c.text, c.limit), c.expected)?
	return ok(c.weight)
}

fn run_neighbor(c Case) Int! {
	which := c.which

	if which == 0 {
		expect_equal(hex_encode(c.data), c.text)?
	} else if which == 1 {
		expect_equal(base64_encode(c.data, false), c.text)?
	} else if which == 2 {
		expect_equal(ascii_decode(c.data), c.expected_text)?
	} else if which == 3 {
		expect_equal(utf16_decode(c.data, true, 4096), c.expected_text)?
	} else if which == 4 {
		expect_equal(utf16_decode(c.data, false, 4096), c.expected_text)?
	} else if which == 5 {
		expect_equal(decode_first(c.scalar, 0), ok(Utf8Scalar(233, 2)))?
	} else {
		expect_equal(decode_last(c.scalar, 2), ok(Utf8Scalar(233, 2)))?
	}

	return ok(c.weight)
}

type BenchData {
	cases List[Case]
}

fn make_fixture() BenchData {
	var cases List[Case] = []
	cases.append(prep_decode(0, null, 0))
	cases.append(prep_decode(0, 0, 0))
	cases.append(prep_decode(0, -1, 0))
	cases.append(prep_decode(1, 0, 0))
	cases.append(prep_decode(2, 0, 0))
	cases.append(prep_decode(2, 1, 0))
	cases.append(prep_decode(2, null, 0))
	cases.append(prep_decode(3, 0, 0))
	cases.append(prep_decode(2, 0, 1))
	cases.append(prep_decode(2, 1, 1))
	cases.append(prep_decode(8192, 0, 0))
	cases.append(prep_decode(8192, 4095, 0))
	cases.append(prep_decode(8192, 4096, 0))
	cases.append(prep_decode(8192, null, 0))
	cases.append(prep_decode(8192, -1, 0))
	cases.append(prep_decode(8192, null, 1))
	cases.append(prep_decode(8192, null, 2))
	cases.append(prep_decode(8193, 4096, 0))
	cases.append(prep_decode(8193, 4095, 0))
	cases.append(prep_decode(1048576, 0, 0))
	cases.append(prep_decode(1048576, 524287, 0))
	cases.append(prep_decode(1048576, 524288, 0))
	cases.append(prep_decode(1048576, null, 0))
	cases.append(prep_decode(1048576, -1, 0))
	cases.append(prep_decode(1048576, null, 1))
	cases.append(prep_decode(1048576, null, 2))
	cases.append(prep_decode(1048577, 524288, 0))
	cases.append(prep_decode(1048577, 524287, 0))
	cases.append(prep_unicode(0))
	cases.append(prep_unicode(1))
	cases.append(prep_neighbor(0))
	cases.append(prep_neighbor(1))
	cases.append(prep_neighbor(2))
	cases.append(prep_neighbor(3))
	cases.append(prep_neighbor(4))
	cases.append(prep_neighbor(5))
	cases.append(prep_neighbor(6))
	return BenchData(cases: cases)
}

bench "hex.limit.empty.none" {
	run_decode(fixture.cases[0])?
}

bench "hex.limit.empty.zero" {
	run_decode(fixture.cases[1])?
}

bench "hex.limit.empty.negative" {
	run_decode(fixture.cases[2])?
}

bench "hex.limit.one.odd" {
	run_decode(fixture.cases[3])?
}

bench "hex.limit.tiny.zero" {
	run_decode(fixture.cases[4])?
}

bench "hex.limit.tiny.exact" {
	run_decode(fixture.cases[5])?
}

bench "hex.limit.tiny.none" {
	run_decode(fixture.cases[6])?
}

bench "hex.limit.tiny.odd.over" {
	run_decode(fixture.cases[7])?
}

bench "hex.limit.tiny.bad.limit" {
	run_decode(fixture.cases[8])?
}

bench "hex.limit.tiny.bad.fit" {
	run_decode(fixture.cases[9])?
}

bench "hex.limit.zero.8192" {
	run_decode(fixture.cases[10])?
}

bench "hex.limit.under.8192" {
	run_decode(fixture.cases[11])?
}

bench "hex.limit.exact.8192" {
	run_decode(fixture.cases[12])?
}

bench "hex.limit.none.8192" {
	run_decode(fixture.cases[13])?
}

bench "hex.limit.negative.8192" {
	run_decode(fixture.cases[14])?
}

bench "hex.limit.bad.first.8192" {
	run_decode(fixture.cases[15])?
}

bench "hex.limit.bad.last.8192" {
	run_decode(fixture.cases[16])?
}

bench "hex.limit.odd.fit.8192" {
	run_decode(fixture.cases[17])?
}

bench "hex.limit.odd.under.8192" {
	run_decode(fixture.cases[18])?
}

bench "hex.limit.zero.1048576" {
	run_decode(fixture.cases[19])?
}

bench "hex.limit.under.1048576" {
	run_decode(fixture.cases[20])?
}

bench "hex.limit.exact.1048576" {
	run_decode(fixture.cases[21])?
}

bench "hex.limit.none.1048576" {
	run_decode(fixture.cases[22])?
}

bench "hex.limit.negative.1048576" {
	run_decode(fixture.cases[23])?
}

bench "hex.limit.bad.first.1048576" {
	run_decode(fixture.cases[24])?
}

bench "hex.limit.bad.last.1048576" {
	run_decode(fixture.cases[25])?
}

bench "hex.limit.odd.fit.1048576" {
	run_decode(fixture.cases[26])?
}

bench "hex.limit.odd.under.1048576" {
	run_decode(fixture.cases[27])?
}

bench "hex.limit.unicode.0" {
	run_decode(fixture.cases[28])?
}

bench "hex.limit.unicode.1" {
	run_decode(fixture.cases[29])?
}

bench "hex.neighbor.hex.encode" {
	run_neighbor(fixture.cases[30])?
}

bench "hex.neighbor.base64.encode" {
	run_neighbor(fixture.cases[31])?
}

bench "hex.neighbor.ascii.decode" {
	run_neighbor(fixture.cases[32])?
}

bench "hex.neighbor.utf16.le" {
	run_neighbor(fixture.cases[33])?
}

bench "hex.neighbor.utf16.be" {
	run_neighbor(fixture.cases[34])?
}

bench "hex.neighbor.utf8.first" {
	run_neighbor(fixture.cases[35])?
}

bench "hex.neighbor.utf8.last" {
	run_neighbor(fixture.cases[36])?
}
