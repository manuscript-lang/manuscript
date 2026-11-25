// conform: tags=testing,tier-stdlib
// conform: phase=test
import (
	MediaType,
	encode_multipart,
	extension_for_media_type,
	form_part,
	format_media_type,
	media_type_for_extension,
	multipart_boundary,
	parse_headers,
	parse_media_type,
	parse_multipart from "@std/net/mime.ms",
	expect_equal, expect_true from "@std/test/test.ms",
)

test "media types parse and format" {
	media := parse_media_type("Text/HTML; Charset=\"utf-8\"; q=\"a\\\"b\"").get()
	expect_equal(media.essence, "text/html")?
	expect_equal(media.params.get_or("charset", ""), "utf-8")?
	expect_equal(media.params.get_or("q", ""), "a\"b")?
	expect_equal(
		format_media_type(parse_media_type("text/plain; charset=utf-8").get()),
		"text/plain; charset=utf-8",
	)?
	expect_true(parse_media_type("text").is_error())?
	expect_true(parse_media_type("a/b; x=\"open").is_error())?
}

test "an escaped closing quote does not end a quoted parameter" {
	// text/plain; name="x\"  (the last quote is a quoted pair)
	expect_true(parse_media_type("text/plain; name=\"x\\\"").is_error())?
	expect_true(parse_media_type("text/plain; name=\"x\\\\\\\"").is_error())?
	expect_true(parse_media_type("text/plain; name=\"x\"y").is_error())?
	expect_true(parse_media_type("text/plain; name=\"").is_error())?

	pair := parse_media_type("text/plain; name=\"x\\\"y\"").get()
	expect_equal(pair.params.get_or("name", ""), "x\"y")?

	slash := parse_media_type("text/plain; name=\"x\\\\\"").get()
	expect_equal(slash.params.get_or("name", ""), "x\\")?
}

test "extension table maps both ways" {
	expect_equal(media_type_for_extension(".JSON") or "", "application/json")?
	expect_equal(media_type_for_extension("png") or "", "image/png")?
	expect_true(media_type_for_extension(".nope") == null)?
	expect_equal(extension_for_media_type("image/svg+xml; x=y") or "", ".svg")?
}

test "headers fold and look up ignoring case" {
	headers := parse_headers(
		"Subject: hello\r\n  world\r\nX-Tag: a\r\nx-tag: b\r\n\r\nbody: no"
	).get()
	expect_equal(headers.get("subject") or "", "hello world")?
	expect_equal(headers.get_all("X-TAG"), ["a", "b"])?
	expect_equal(headers.fields.length(), 3)?
	expect_true(parse_headers("no colon").is_error())?
	expect_true(parse_headers(" folded first").is_error())?
}

test "multipart round-trips fields and files" {
	parts := [
		form_part("title", "Hello".to_bytes()),
		form_part(
			"upload",
			"line1\r\nline2".to_bytes(),
			filename: "a b.txt",
			content_type: "text/plain",
		),
	]
	body := encode_multipart(parts, "XyZ")
	back := parse_multipart(body, "XyZ").get()
	expect_equal(back.length(), 2)?
	expect_equal(back[0].name, "title")?
	expect_equal(back[0].data.decode_utf8() or "", "Hello")?
	expect_equal(back[1].filename, "a b.txt")?
	expect_equal(back[1].data.decode_utf8() or "", "line1\r\nline2")?
	expect_equal(back[1].headers.get("content-type") or "", "text/plain")?
}

test "multipart rejects a missing closing delimiter" {
	expect_true(parse_multipart("--b\r\n\r\nx".to_bytes(), "b").is_error())?
	expect_true(parse_multipart("junk".to_bytes(), "b").is_error())?
	expect_equal(multipart_boundary("multipart/form-data; boundary=abc") or "", "abc")?
	expect_true(multipart_boundary("text/plain") == null)?
}

test "multipart accepts only transport padding before delimiter line endings" {
	for padding in ["", " ", "\t", " \t \t"] {
		body := f"--b{padding}\r\nX-Label: first\r\n\r\n \tpayload \r\n--b{padding}\r\n\r\n\r\n--b--{padding}\r\nepilogue".to_bytes()
		parts := parse_multipart(body, "b")?
		expect_equal(parts.length(), 2)?
		expect_equal(parts[0].headers.get("X-Label"), "first")?
		expect_equal(parts[0].data, " \tpayload ".to_bytes())?
		expect_equal(parts[1].data, "".to_bytes())?
	}

	for padding in ["x", "\n", "\u{b}", "\u{a0}", "\r"] {
		body := f"--b{padding}\r\n\r\nx\r\n--b--\r\n".to_bytes()
		expect_equal(parse_multipart(body, "b").err().kind, "EBADMSG")?
	}
}

test "line breaks in field and file names cannot inject header lines" {
	hostile := "a\r\nContent-Type: text/html"
	part := form_part(hostile.clone(), "x".to_bytes(), hostile)
	expect_equal(part.headers.fields.length(), 1)?

	body := encode_multipart([part], "b")
	parts := parse_multipart(body, "b")?
	expect_equal(parts.length(), 1)?
	expect_equal(parts[0].headers.fields.length(), 1)?
	expect_equal(parts[0].name, "a%0D%0AContent-Type: text/html")?
	expect_equal(parts[0].data, "x".to_bytes())?
	expect_equal(
		format_media_type(MediaType(essence: "a/b", params: {"k": "v\nX: y"})),
		"a/b; k=\"v%0AX: y\"",
	)?
}

test "a part may be only headers or empty, as RFC 2046 allows" {
	headers_only := parse_multipart("--b\r\nX-A: 1\r\n--b--\r\n".to_bytes(), "b")?
	expect_equal(headers_only.length(), 1)?
	expect_equal(headers_only[0].headers.get("x-a") or "", "1")?
	expect_equal(headers_only[0].data, "".to_bytes())?

	closed := parse_multipart("--b\r\nX-A: 1\r\n\r\n--b--\r\n".to_bytes(), "b")?
	expect_equal(closed.length(), 1)?
	expect_equal(closed[0].data, "".to_bytes())?

	empty := parse_multipart(
		"--b\r\n--b\r\nX-A: 2\r\n\r\nv\r\n--b--\r\n".to_bytes(),
		"b",
	)?
	expect_equal(empty.length(), 2)?
	expect_equal(empty[0].headers.fields.length(), 0)?
	expect_equal(empty[1].data, "v".to_bytes())?

	// A section that is neither headers nor empty is still rejected.
	expect_true(
		parse_multipart(
			"--b\r\nnot a header\r\n--b--\r\n".to_bytes(),
			"b",
		).is_error()
	)?
}

test "multipart names are read as browsers write them: a backslash is literal" {
	body := (
		"--b\r\nContent-Disposition: form-data; name=\"up\"; filename=\"C:\\x\\y.txt\"\r\n\r\n1\r\n"
		+ "--b\r\nContent-Disposition: form-data; name=\"tail\\\"; filename=\"a\\\"\r\n\r\n2\r\n"
		+ "--b\r\nContent-Disposition: form-data; name=\"q%22uote\" ; filename=\"x;y.txt\"\r\n\r\n3\r\n"
		+ "--b\r\nContent-Disposition: form-data; NAME=plain; filename=f.txt\r\n\r\n4\r\n--b--\r\n"
	)
	parts := parse_multipart(body.to_bytes(), "b")?
	expect_equal(parts[0].name, "up")?
	expect_equal(parts[0].filename, "C:\\x\\y.txt")?
	expect_equal(parts[1].name, "tail\\")?
	expect_equal(parts[1].filename, "a\\")?
	expect_equal(parts[2].name, "q%22uote")?
	expect_equal(parts[2].filename, "x;y.txt")?
	expect_equal(parts[3].name, "plain")?
	expect_equal(parts[3].filename, "f.txt")?
}

test "form_part writes a backslash literally and a quote as %22, and parse_multipart reads both back" {
	part := form_part("a\\b", "x".to_bytes(), "C:\\dir\\f \"1\".txt")
	disposition := part.headers.get("Content-Disposition") or ""
	expect_equal(disposition, "form-data; name=\"a\\b\"; filename=\"C:\\dir\\f %221%22.txt\"")?

	back := parse_multipart(encode_multipart([part], "b"), "b")?
	expect_equal(back[0].name, "a\\b")?
	expect_equal(back[0].filename, "C:\\dir\\f %221%22.txt")?
}
