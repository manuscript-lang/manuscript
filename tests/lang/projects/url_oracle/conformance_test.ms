import (
	hex_decode, hex_encode from "@std/data/encoding.ms",
	QueryEntry,
	Url,
	decode_component,
	encode_component,
	format,
	format_query,
	parse,
	parse_query,
	resolve from "@std/net/url.ms",
	fail from "@std/test/test.ms",

	files from "@oracle",
)

// Replays data/url.tsv, the corpus recorded from the C implementation of
// `@std/net/url`: one case per line as `operation<TAB>inputs...<TAB>=><TAB>outcome`. A
// text is `x` followed by the hex of its UTF-8 bytes, `-` is a missing value, and an
// error is `err` and its kind.

fn hex(value String) String {
	return f"x{hex_encode(value.to_bytes())}"
}

fn text(token String) String {
	digits := token.view(1, token.length())
	bytes := hex_decode(digits, null) | .get_or("".to_bytes())
	return bytes.decode_utf8() or ""
}

fn opt(value String?) String {
	if value == null { return "-" }
	return hex(value)
}

fn fault(cause Error) String {
	return f"err {cause.kind}"
}

fn url_text(u Url) String {
	port := if u.port == null { "-" } else { f"{u.port or 0}" }
	return f"ok {hex(u.scheme)} {hex(u.host)} {hex(u.path)} {hex(u.fragment)} {opt(u.query)} {port} {u.omit_host}"
}

fn parsed(input String) String {
	outcome := parse(input)
	if outcome.is_error() { return fault(outcome.err()) }

	return url_text(outcome.get_or(Url("", "", "", "", null, null)))
}

fn formatted(input String) String {
	outcome := parse(input)
	if outcome.is_error() { return fault(outcome.err()) }

	rendered := format(outcome.get_or(Url("", "", "", "", null, null)))
	if rendered.is_error() { return fault(rendered.err()) }

	return f"ok {hex(rendered.get_or(""))}"
}

fn resolved(base, reference String) String {
	outcome := parse(base)
	if outcome.is_error() { return fault(outcome.err()) }

	joined := resolve(outcome.get_or(Url("", "", "", "", null, null)), reference)
	if joined.is_error() { return fault(joined.err()) }

	return url_text(joined.get_or(Url("", "", "", "", null, null)))
}

fn decoded(input String) String {
	outcome := decode_component(input)
	if outcome.is_error() { return fault(outcome.err()) }

	return f"ok {hex(outcome.get_or(""))}"
}

fn queried(input String) String {
	outcome := parse_query(input, null)
	if outcome.is_error() { return fault(outcome.err()) }

	entries := outcome.get_or(List[QueryEntry]())
	return f"ok {entries.map(e => f"{hex(e.key)}={hex(e.value)}").join(",")}"
}

fn requeried(input String) String {
	outcome := parse_query(input, null)
	if outcome.is_error() { return fault(outcome.err()) }

	return f"ok {hex(format_query(outcome.get_or(List[QueryEntry]())))}"
}

fn answer(f List[String]) String {
	op := f[0]
	if op == "parse" { return parsed(text(f[1])) }
	if op == "format" { return formatted(text(f[1])) }
	if op == "resolve" { return resolved(text(f[1]), text(f[2])) }
	if op == "decode" { return decoded(text(f[1])) }
	if op == "encode" { return f"ok {hex(encode_component(text(f[1])))}" }
	if op == "query" { return queried(text(f[1])) }
	if op == "requery" { return requeried(text(f[1])) }

	return f"unknown case {op}"
}

test "url operations match the recorded corpus" {
	raw := files().read("url.tsv", null).get_or("".to_bytes())
	data := raw.decode_utf8() or ""
	var checked = 0
	var failures = List[String]()

	for line in data.split("\n") {
		if line.is_empty() or line.starts_with("#") { continue }

		f := line.split("\t").collect()
		want := f[f.length() - 1]
		got := answer(f)
		checked += 1
		if got != want and failures.length() < 10 {
			failures.append(f"{line} -> {got}")
		}
	}

	if not failures.is_empty() {
		return fail(f"{failures.length()} mismatches, first:\n{failures.join("\n")}")
	}
	if checked < 3000 { return fail(f"only {checked} cases replayed") }

	return ok()
}
