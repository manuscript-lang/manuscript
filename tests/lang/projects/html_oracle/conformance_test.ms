import (
	hex_encode from "@std/data/encoding.ms",
	HtmlNode, parse, unescape from "@std/data/html.ms",
	fail from "@std/test/test.ms",

	files from "@oracle",
)

// Replays data/html.tsv, the corpus recorded from the C character-reference natives:
// one case per line as
// `mode<TAB>input<TAB>=><TAB>output`. Mode `u` is the public `unescape`; `t` decodes the input as the text of a
// paragraph and `a` as an attribute value, through the parser. An output is `x` and the
// hex of its UTF-8 bytes.

fn hex(value String) String {
	return f"x{hex_encode(value.to_bytes())}"
}

// The text between the « and » markers of the tree dump of `markup`.
fn marked(markup String) String {
	tree := parse(markup).get_or_else(cause => HtmlNode.Document([]))
	parts := f"{tree}".split("«")
	if parts.length() < 2 { return "<missing>" }

	return parts[1].split("»")[0]
}

fn answer(mode, input String) String {
	if mode == "u" { return hex(unescape(input)) }
	if mode == "t" { return hex(marked(f"<p>«{input}»</p>")) }

	return hex(marked(f"<a href=\"«{input}»\">"))
}

test "html character references match the recorded corpus" {
	raw := files().read("html.tsv", null).get_or("".to_bytes())
	data := raw.decode_utf8() or ""
	var checked = 0
	var failures = List[String]()

	for line in data.split("\n") {
		if line.is_empty() or line.starts_with("#") { continue }

		f := line.split("\t")
		got := answer(f[0], f[1])
		checked += 1
		if got != f[3] and failures.length() < 10 {
			failures.append(f"{line} -> {got}")
		}
	}

	if not failures.is_empty() {
		return fail(f"{failures.length()} mismatches, first:\n{failures.join("\n")}")
	}
	if checked < 8000 { return fail(f"only {checked} cases replayed") }

	return ok()
}
