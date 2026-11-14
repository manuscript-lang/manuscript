import (
	parse from "@std/data/html.ms",
	stdout from "@std/io/io.ms",
	StringBuilder from "@std/string_builder.ms",
	monotonic from "@std/time.ms",
)

// A page of nested blocks, inline formatting, attributes, entities, lists, tables and a
// script, the shape real documents have.
fn document(count: Int) String:
	var sb = StringBuilder()
	sb.append(
		"<!DOCTYPE html><html><head><title>t &amp; u</title><style>p\{color:red\}</style></head><body>"
	)

	for i in 0..count:
		sb.append(
			"<div class=\"card\" id=\"c{i}\"><h2>Title {i}</h2><p>Some <b>bold</b> &amp; <a href=\"/x?a=1&amp;b={i}\">link</a> text<br>"
		)
		sb.append(
			"<ul><li>one<li>two<li>three</ul><table><tr><td>a<td>b</table><!-- note --></div>\n"
		)

	sb.append("<script>var a = 1 < 2;</script></body></html>")
	return sb.build()

fn parse_ok(text: String) Int:
	if parse(text).is_ok(): return 1
	return 0

fn deep(count: Int) String:
	return "<div>".repeat(count).get("")

// Parses the page and a deeply nested document, best of 50 runs each, in microseconds.
fn main() Unit:
	text := document(2000)
	nested := deep(5000)
	var best = 1000000000000
	var best_deep = 1000000000000
	var ok = 0

	for run in 0..50:
		started := monotonic()
		ok = parse_ok(text) + run * 0

		elapsed := monotonic().difference(started).to_nanoseconds()
		if elapsed < best: best = elapsed

	for run in 0..20:
		started := monotonic()
		ok = ok + parse_ok(nested) + run * 0

		elapsed := monotonic().difference(started).to_nanoseconds()
		if elapsed < best_deep: best_deep = elapsed

	_ignored := stdout().write(
		"ms html bytes={text.byte_length()} ok={ok} page_us={best / 1000} deep5000_us={best_deep / 1000}\n"
	)
