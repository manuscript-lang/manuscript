import (
	quote_text from "@std/data/quote.ms",
	histogram from "@std/data/histogram.ms",
	ClientResponse, HttpResponseMetadata, headers from "@std/net/http.ms",
	expect_equal from "@std/test/test.ms",
)

test "JSON-style quoting uses short and hexadecimal control escapes":
	try expect_equal(quote_text("\n\t\r\u{8}\u{c}", false), "\"\\n\\t\\r\\b\\f\"")
	try expect_equal(quote_text("\u{1}\u{7f}\u{80}", false), "\"\\u0001\\u007f\u{80}\"")
	try expect_equal(quote_text("\u{80}", true), "\"\\u0080\"")

test "buffered response metadata is already an independent copy":
	var fields = headers()
	try fields.append("x-test", "original")

	response := ClientResponse(HttpResponseMetadata(200, fields), "ok".to_bytes())
	var copied = response.metadata()
	copied.status = 201
	try copied.headers.append("x-test", "new")
	try expect_equal(response.metadata().status, 200)
	try expect_equal(response.metadata().headers.values("x-test"), ["original"])
	try expect_equal(copied.headers.values("x-test"), ["original", "new"])

fn early_return() Int:
	return 7

fn error_return() Unit!:
	return error(Error("expected"))

test "histogram times normal early returns and error Results":
	var h = histogram()
	try expect_equal(h.time(early_return), 7)
	try expect_equal(h.count(), 1)
	try expect_equal(h.time(error_return).is_error(), true)
	try expect_equal(h.count(), 2)
