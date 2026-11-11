import (
	Bytes, BytesBuilder from "@std/bytes.ms",
	ReadStream, Source from "@std/io/io.ms",
	from_list from "@std/io/streams.ms",
	Part,
	encode_multipart,
	form_part,
	multipart_parts,
	parse_multipart from "@std/net/mime.ms",
	expect_equal, fail from "@std/test/test.ms",
)

// Hands out the chunks in order, then ends.
type Chunks:
	data: Bytes
	size: Int
	at: Int

impl Source[Bytes] for Chunks:
	var fn next() Bytes?!:
		if self.at >= self.data.length(): return ok(none)

		var end = self.at + self.size
		if end > self.data.length(): end = self.data.length()

		piece := try self.data.slice(self.at, end)
		self.at = end
		return ok(piece)

	var fn close() Unit!:
		return ok(unit)

fn chunked(data: Bytes, size: Int) ReadStream[Bytes]:
	return ReadStream[Bytes](Chunks(data, size, 0))

fn read_parts(body: Bytes, size: Int, max_part_bytes: Int? = none) List[Part]!:
	var parts = multipart_parts(chunked(body, size), "XyZ", max_part_bytes)
	var out: List[Part] = []

	while true:
		next := try parts.next()

		if part := next:
			out.append(part)
		else:
			break

	return ok(out)

fn sample() Bytes:
	return encode_multipart(
		[
			form_part("title", "hello".to_bytes()),
			form_part(
				"file",
				"line1\r\nline2\r\n--not-a-delimiter".to_bytes(),
				filename: "a.txt",
				content_type: "text/plain",
			),
			form_part("empty", "".to_bytes()),
		],
		"XyZ",
	)

test "parts match parse_multipart under every chunk size":
	body := "preamble ignored\r\n".to_bytes().concat(sample())
	expected := try parse_multipart(body.clone(), "XyZ")
	for size in 1..body.length() + 1:
		if (try read_parts(body.clone(), size)) != expected: return fail(
			"chunk size {size}"
		)
	try expect_equal(expected.length(), 3)
	try expect_equal(expected[1].filename, "a.txt")

test "a body without the closing delimiter is InvalidData":
	body := "--XyZ\r\nContent-Disposition: form-data; name=a\r\n\r\nvalue".to_bytes()
	outcome := read_parts(body, 5)
	try expect_equal(outcome.err().kind, "EBADMSG")

test "the part budget reports LimitExceeded":
	big := encode_multipart([form_part("f", "x".repeat(500).get("").to_bytes())], "XyZ")
	outcome := read_parts(big.clone(), 64, 100)
	try expect_equal(outcome.err().kind, "EOVERFLOW")
	try expect_equal((try read_parts(big, 64, 1000)).length(), 1)

test "a preamble longer than the part budget is ignored under every chunk size":
	body := "p".repeat(80).get("").to_bytes().concat(
		"\r\n--XyZ\r\n\r\nx\r\n--XyZ--\r\n".to_bytes()
	)

	for size in 1..body.length() + 1:
		parts := try read_parts(body.clone(), size, 20)
		try expect_equal(parts.length(), 1)
		try expect_equal(parts[0].data, "x".to_bytes())

test "a non-UTF-8 header block is InvalidData in both parsers":
	var body = BytesBuilder()
	body.append_bytes(
		"--XyZ\r\nContent-Disposition: form-data; name=f\r\nX-Test: ".to_bytes()
	)
	body.append(255)
	body.append_bytes("\r\n\r\nx\r\n--XyZ--\r\n".to_bytes())

	bytes := body.build()
	try expect_equal(parse_multipart(bytes.clone(), "XyZ").err().kind, "EBADMSG")
	for size in [1, 7, 200]:
		try expect_equal(read_parts(bytes.clone(), size).err().kind, "EBADMSG")

test "an Int-max part limit does not overflow on a partial part":
	body := "--XyZ\r\n\r\nx\r\n--XyZ--\r\n".to_bytes()

	for size in 1..body.length() + 1:
		parts := try read_parts(body.clone(), size, 9223372036854775807)
		try expect_equal(parts.length(), 1)
		try expect_equal(parts[0].data, "x".to_bytes())

test "transport padded multipart delimiters survive every chunk size":
	body := "preamble\r\n--XyZ \t\r\nX-Label: first\r\n\r\n \tpayload \r\n--XyZ\t \r\n\r\n\r\n--XyZ-- \t\r\nepilogue".to_bytes()
	expected := try parse_multipart(body, "XyZ")
	try expect_equal(expected.length(), 2)
	try expect_equal(expected[0].data, " \tpayload ".to_bytes())
	try expect_equal(expected[1].data, "".to_bytes())
	for size in 1..body.length() + 1:
		try expect_equal(try read_parts(body.clone(), size), expected)

test "transport padding does not bypass streaming part budget":
	padding := " ".repeat(40).get("")
	body := "--XyZ{padding}\r\n\r\nx\r\n--XyZ--\r\n".to_bytes()
	for size in 1..body.length() + 1:
		try expect_equal(read_parts(body.clone(), size, 10).err().kind, "EOVERFLOW")

test "padded multipart sections retain exact raw budget boundary":
	body := "--XyZ \t\r\n\r\nx\r\n--XyZ--\r\n".to_bytes()

	for size in 1..body.length() + 1:
		parts := try read_parts(body.clone(), size, 7)
		try expect_equal(parts.length(), 1)
		try expect_equal(parts[0].data, "x".to_bytes())
		try expect_equal(read_parts(body.clone(), size, 6).err().kind, "EOVERFLOW")

// Replaces the byte at `at` with `value`.
fn with_byte(data: Bytes, at: Int, value: Int) Bytes:
	var out = BytesBuilder()
	out.append_bytes(data.slice(0, at).get("".to_bytes()))
	out.append(value.to_uint8().get(0))
	out.append_bytes(data.slice(at + 1, data.length()).get("".to_bytes()))
	return out.build()

// Compares the two parsers on one body: the same error kind, or the same parts.
fn agree(body: Bytes, size: Int) String:
	whole := parse_multipart(body.clone(), "XyZ")
	stream := read_parts(body.clone(), size)

	if whole.is_error() or stream.is_error():
		if whole.is_error() != stream.is_error(): return "one failed: parse {whole.is_error()}, stream {stream.is_error()}"
		if whole.err().kind != stream.err().kind: return "kinds differ: {whole.err().kind}, {stream.err().kind}"

		return ""

	if whole.get() != stream.get(): return "parts differ"

	return ""

test "parts and parse_multipart agree on corrupted and truncated bodies":
	body := sample()
	var cases: List[Bytes] = []

	for at in 0..body.length():
		if at % 5 != 0: continue

		for value in [13, 10, 45, 0]:
			cases.append(with_byte(body.clone(), at, value))

	for cut in 0..body.length():
		if cut % 7 == 0: cases.append(body.slice(0, cut).get("".to_bytes()))

	for index in 0..cases.length():
		for size in [1, 3, 64]:
			verdict := agree(cases[index].clone(), size)
			if verdict != "": return fail("case {index}, chunk {size}: {verdict}")

fn empty_chunks(data: Bytes, size: Int) List[Bytes]:
	var chunks: List[Bytes] = []
	var at = 0

	while at < data.length():
		chunks.append("".to_bytes())

		stop := (at + size).min(data.length())
		chunks.append(data.slice(at, stop).get())
		at = stop

	return chunks

test "fragmented multipart bodies keep binary bytes and delimiter prefixes":
	var payload = BytesBuilder()

	for unused in 0..2048:
		payload.append_bytes("--Xy-prefix\r\n--Xy\r\n".to_bytes())
		payload.append(255)

	data := payload.build()
	body := encode_multipart(
		[
			form_part("binary", data.clone()),
			form_part("end", "tail".to_bytes()),
		],
		"XyZ",
	)

	for size in [1, 2, 5, 7, 64, 1024]:
		var parts = multipart_parts(from_list(empty_chunks(body, size)), "XyZ", none)

		if first := try parts.next():
			try expect_equal(first.name, "binary")
			try expect_equal(first.data, data)
		else:
			return fail("missing binary part at chunk size {size}")

		if second := try parts.next():
			try expect_equal(second.data, "tail".to_bytes())
		else:
			return fail("missing trailing part at chunk size {size}")

		try expect_equal((try parts.next()).is_none(), true)

test "retrying an invalid fragmented multipart section retains the error":
	body := "--XyZ\r\nnot-a-header\r\n\r\nvalue-value-value\r\n--XyZ".to_bytes()
	var chunks = empty_chunks(body, 3)
	chunks.append("".to_bytes())

	var parts = multipart_parts(from_list(chunks), "XyZ", none)
	try expect_equal(parts.next().err().kind, "EBADMSG")
	try expect_equal(parts.next().err().kind, "EBADMSG")
