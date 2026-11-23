import (
	escape, parse, unescape from "@std/data/html.ms",
	StringBuilder from "@std/string_builder.ms",

	words from "./src/harness.ms",
)

fn html_doc(count: Int) String:
	var sb = StringBuilder()
	sb.append("<div>")
	for i in 0..count:
		sb.append(f"<p class=\"row\" id=\"r{i}\">item <b>{i}</b> &amp; more</p>")
	sb.append("</div>")
	return sb.build()

type BenchData:
	html: String
	text: String

fn make_fixture() BenchData:
	html := html_doc(2000)
	text := words(2000).join(" <&> ")
	return BenchData(html: html, text: text)

bench "html.parse" per 2000:
	parse(fixture.html).is_ok()

bench "html.escape_unescape" per 2000:
	fixture.text | escape | unescape | .length()
