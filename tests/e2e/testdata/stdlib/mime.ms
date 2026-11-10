import (
	expect_equal, expect_true from "@std/test/test.ms",
	parse_media_type,
	format_media_type,
	media_type_for_extension,
	extension_for_media_type,
	parse_headers,
	parse_multipart,
	encode_multipart,
	form_part,
	multipart_boundary,
	MediaType from "@std/net/mime.ms",
)

test "media types parse and format":
	media := parse_media_type("Text/HTML; Charset=\"utf-8\"; q=\"a\\\"b\"").get()
	try expect_equal(media.essence, "text/html")
	try expect_equal(media.params.get("charset").get(""), "utf-8")
	try expect_equal(media.params.get("q").get(""), "a\"b")
	try expect_equal(
		format_media_type(parse_media_type("text/plain; charset=utf-8").get()),
		"text/plain; charset=utf-8"
	)
	try expect_true(parse_media_type("text").is_error())
	try expect_true(parse_media_type("a/b; x=\"open").is_error())

test "an escaped closing quote does not end a quoted parameter":
	// text/plain; name="x\"  (the last quote is a quoted pair)
	try expect_true(parse_media_type("text/plain; name=\"x\\\"").is_error())
	try expect_true(parse_media_type("text/plain; name=\"x\\\\\\\"").is_error())
	try expect_true(parse_media_type("text/plain; name=\"x\"y").is_error())
	try expect_true(parse_media_type("text/plain; name=\"").is_error())

	pair := parse_media_type("text/plain; name=\"x\\\"y\"").get()
	try expect_equal(pair.params.get("name").get(""), "x\"y")

	slash := parse_media_type("text/plain; name=\"x\\\\\"").get()
	try expect_equal(slash.params.get("name").get(""), "x\\")

test "extension table maps both ways":
	try expect_equal(media_type_for_extension(".JSON").get(""), "application/json")
	try expect_equal(media_type_for_extension("png").get(""), "image/png")
	try expect_true(media_type_for_extension(".nope").is_none())
	try expect_equal(extension_for_media_type("image/svg+xml; x=y").get(""), ".svg")

test "headers fold and look up ignoring case":
	headers := parse_headers(
		"Subject: hello\r\n  world\r\nX-Tag: a\r\nx-tag: b\r\n\r\nbody: no"
	).get()
	try expect_equal(headers.get("subject").get(""), "hello world")
	try expect_equal(headers.get_all("X-TAG"), ["a", "b"])
	try expect_equal(headers.fields.length(), 3)
	try expect_true(parse_headers("no colon").is_error())
	try expect_true(parse_headers(" folded first").is_error())

test "multipart round-trips fields and files":
	parts := [
		form_part("title", "Hello".to_bytes()),
		form_part(
			"upload", "line1\r\nline2".to_bytes(), filename: "a b.txt",
			content_type: "text/plain"
		)
	]
	body := encode_multipart(parts, "XyZ")
	back := parse_multipart(body, "XyZ").get()
	try expect_equal(back.length(), 2)
	try expect_equal(back[0].name, "title")
	try expect_equal(back[0].data.decode_utf8().get(""), "Hello")
	try expect_equal(back[1].filename, "a b.txt")
	try expect_equal(back[1].data.decode_utf8().get(""), "line1\r\nline2")
	try expect_equal(back[1].headers.get("content-type").get(""), "text/plain")

test "multipart rejects a missing closing delimiter":
	try expect_true(parse_multipart("--b\r\n\r\nx".to_bytes(), "b").is_error())
	try expect_true(parse_multipart("junk".to_bytes(), "b").is_error())
	try expect_equal(
		multipart_boundary("multipart/form-data; boundary=abc").get(""), "abc"
	)
	try expect_true(multipart_boundary("text/plain").is_none())

test "multipart accepts only transport padding before delimiter line endings":
	for padding in ["", " ", "\t", " \t \t"]:
		body := "--b{padding}\r\nX-Label: first\r\n\r\n \tpayload \r\n--b{padding}\r\n\r\n\r\n--b--{padding}\r\nepilogue".to_bytes()
		parts := try parse_multipart(body, "b")
		try expect_equal(parts.length(), 2)
		try expect_equal(parts[0].headers.get("X-Label"), "first")
		try expect_equal(parts[0].data, " \tpayload ".to_bytes())
		try expect_equal(parts[1].data, "".to_bytes())

	for padding in ["x", "\n", "\u{b}", "\u{a0}", "\r"]:
		body := "--b{padding}\r\n\r\nx\r\n--b--\r\n".to_bytes()
		try expect_equal(parse_multipart(body, "b").err().kind, "EBADMSG")
