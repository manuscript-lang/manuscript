// conform: tags=testing,tier-io
// conform: phase=test
import (
	histogram from "@std/data/histogram.ms",
	quote_text from "@std/data/quote.ms",
	ClientResponse, HttpResponseMetadata, headers from "@std/net/http.ms",
	expect_equal from "@std/test/test.ms",
)

test "JSON-style quoting uses short and hexadecimal control escapes":
	expect_equal(quote_text("\n\t\r\u{8}\u{c}", false), "\"\\n\\t\\r\\b\\f\"")?
	expect_equal(quote_text("\u{1}\u{7f}\u{80}", false), "\"\\u0001\\u007f\u{80}\"")?
	expect_equal(quote_text("\u{80}", true), "\"\\u0080\"")?

test "buffered response metadata is already an independent copy":
	var fields = headers()
	fields.append("x-test", "original")?

	response := ClientResponse(HttpResponseMetadata(200, fields), "ok".to_bytes())
	var copied = response.metadata()
	copied.status = 201
	copied.headers.append("x-test", "new")?
	expect_equal(response.metadata().status, 200)?
	expect_equal(response.metadata().headers.values("x-test"), ["original"])?
	expect_equal(copied.headers.values("x-test"), ["original", "new"])?

fn early_return() Int:
	return 7

fn error_return() Unit!:
	return error(Error("expected"))

test "histogram times normal early returns and error Results":
	var h = histogram()
	expect_equal(h.time(early_return), 7)?
	expect_equal(h.count(), 1)?
	expect_equal(h.time(error_return).is_error(), true)?
	expect_equal(h.count(), 2)?
