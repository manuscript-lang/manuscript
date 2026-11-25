import (
	crc32 from "@std/data/checksum.ms",
	hex_decode, hex_encode from "@std/data/encoding.ms",
	HtmlNode, HtmlOptions, parse from "@std/data/html.ms",
	expect_equal, fail from "@std/test/test.ms",

	files from "@assets",
)

// Replays the cases recorded from Go's golang.org/x/net/html (parse trees for 2,000
// documents, including malformed markup, tables, foreign content, templates and the
// adoption agency algorithm). Each line is
// `parse <hex input> <max bytes> <max depth> <max nodes> => <result>`, where the result
// renders the tree as `D[..]` documents, `E<name>,<namespace>{attributes}[..]`
// elements, and `T`, `C` and `Y` text, comment and doctype nodes, all hex-encoded.

fn hx(text String) String {
	return hex_encode(text.to_bytes())
}

fn unhex(token String) String {
	h := token.view(1, token.length()).clone()
	if h == "" { return "" }
	if bytes := hex_decode(h, null) { return bytes.decode_utf8() or "" }

	return ""
}

fn limit(token String) Int? {
	if token == "-" { return null }
	return token.parse_int()
}

fn dump(node HtmlNode, var out String) Void {
	match node {
		Document(children) => {
			out += "D["
			for child in children { dump(child, out) }
			out += "]"
		}
		Element(tag, namespace, attributes, children) => {
			out += f"E{hx(tag)},{hx(namespace)}\{"
			for a in attributes { out += f"{hx(a.name)},{hx(a.namespace)},{hx(a.value)};" }
			out += "}["
			for child in children { dump(child, out) }
			out += "]"
		}
		Text(text) => out += f"T{hx(text)};"
		Comment(text) => out += f"C{hx(text)};"
		Doctype(name, public_id, system_id) => {
			out += f"Y{hx(name)},{hx(public_id)},{hx(system_id)};"
		}
	}
}

fn render(result HtmlNode!) String {
	if value := result {
		var sb = ""
		dump(value, sb)
		return f"ok {sb}"
	}

	if result.err().kind == "EOVERFLOW" { return "err LimitExceeded" }

	return "err InvalidInput"
}

fn corpus() String! {
	bytes := files().read("oracle.tsv", null)?
	return ok(bytes.decode_utf8() or "")
}

test "parse matches the recorded Go html trees" {
	text := corpus()?
	var cases = 0

	for line in text.lines() {
		f := line.split("\t")
		if f[0] != "parse" { continue }

		options := HtmlOptions(
			max_bytes: limit(f[2]),
			max_depth: limit(f[3]),
			max_nodes: limit(f[4]),
		)
		got := render(parse(unhex(f[1]), options))
		if got != f[f.length() - 1] {
			return fail(
				f"case {cases}: {line.view(0, line.length().min(160))}\n  want {f[f.length() - 1].view(0, f[f.length() - 1].length().min(300))}\n  got  {got.view(0, got.length().min(300))}"
			)
		}

		cases += 1
	}

	expect_equal(cases > 2000, true)?
}

test "parse trees keep their size and checksum for the recorded large documents" {
	text := corpus()?
	var cases = 0

	for line in text.lines() {
		f := line.split("\t")
		if f[0] != "parsehash" { continue }

		got := render(parse(unhex(f[1])))
		body := got.cut_prefix("ok ")
		if body == null { return fail(f"parse failed: {got}") }

		tree := body
		summary := f"ok {tree.length()} {checksum_hex(tree)}"
		if summary != f[f.length() - 1] {
			return fail(f"{summary} != {f[f.length() - 1]}")
		}

		cases += 1
	}

	expect_equal(cases, 4)?
}

fn checksum_hex(text String) String {
	return crc32(text.to_bytes()).to_hex()
}
