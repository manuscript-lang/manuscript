import (
	Url,
	decode_component,
	encode_component,
	format,
	parse,
	parse_query,
	resolve from "@std/net/url.ms",
	FileTree from "@std/os/tree.ms",
	expect_equal from "@std/test/test.ms",

	Case, cases from "./json_side.ms",
	files from "@suite",
)

// Go's `net/url` test tables (src/net/url/url_test.go, dumped to `data/cases.json` with
// the expected values the Go tests assert). `@std/net/url` reads RFC 3986 URLs the way
// Go does, so each table must agree. A case outside `expect-fail.txt` must pass; a
// listed case must still fail, so the list only ever shrinks. A reason starting
// `by design:` is a permanent decision. Case ids are `<table>#<index>`.

fn text(tree: FileTree, path: String) String:
	return tree.read(path, null).get_or("".to_bytes()).decode_utf8() or ""

fn field(item: Case, key: String) String:
	return item.fields.get_or(key, "")

fn flag(item: Case, key: String) Bool:
	return item.flags.get_or(key, false)

fn port_text(url: Url) String:
	if port := url.port: return port.to_string()
	return ""

// `parse` table: the URL parses to the expected parts and formats back to the expected text;
// user information and opaque URLs are not part of the `Url` type, so they must be
// rejected.
fn parse_ok(item: Case) Bool:
	parsed := parse(field(item, "in"))
	if flag(item, "has_user") or flag(item, "opaque"): return parsed.is_error()
	if parsed.is_error(): return false

	url := parsed.get_or(Url("", "", "", "", null, null))
	if url.scheme != field(item, "scheme") or url.host != field(item, "host"): return false
	if port_text(url) != field(item, "port"): return false

	formatted := format(url)
	return formatted.is_ok() and formatted.get_or("") == field(item, "roundtrip")

// `parse_errors` table: whether Parse rejects the input.
fn parse_error_ok(item: Case) Bool:
	return parse(field(item, "in")).is_error() == flag(item, "err")

fn resolve_ok(item: Case) Bool:
	base := parse(field(item, "base"))
	if base.is_error(): return false

	resolved := resolve(
		base.get_or(Url("", "", "", "", null, null)),
		field(item, "rel"),
	)
	if resolved.is_error(): return false

	formatted := format(resolved.get_or(Url("", "", "", "", null, null)))
	return formatted.is_ok() and formatted.get_or("") == field(item, "expected")

fn unescape_ok(item: Case) Bool:
	decoded := decode_component(field(item, "in"))
	if flag(item, "err"): return decoded.is_error()

	return decoded.is_ok() and decoded.get_or("") == field(item, "out")

// Encoding is checked as a round trip: the escaped text decodes back to the input.
fn escape_ok(item: Case) Bool:
	original := field(item, "in")
	decoded := decode_component(encode_component(original))
	return decoded.is_ok() and decoded.get_or("") == original

fn query_ok(item: Case) Bool:
	parsed := parse_query(field(item, "query"), null)
	if not flag(item, "ok"): return parsed.is_error()
	if parsed.is_error(): return false

	var grouped = Map[String, List[String]]()

	for entry in parsed.get_or([]):
		if values := grouped.get(entry.key):
			var more = values.clone()
			more.append(entry.value.clone())
			grouped.add(entry.key.clone(), more)
		else: grouped.add(entry.key.clone(), [entry.value.clone()])

	if grouped.length() != item.expected.length(): return false

	for member in item.expected.entries():
		if grouped.get_or(member.key, []) != member.value: return false
	return true

fn check(table: String, index: Int, item: Case) Bool:
	if table == "parse": return parse_ok(item)
	if table == "parse_errors": return parse_error_ok(item)
	if table == "resolve": return resolve_ok(item)
	if table == "unescape": return unescape_ok(item)
	if table == "query": return query_ok(item)

	return escape_ok(item)

test "Go net/url tables agree with the parser except for the listed cases":
	tree := files()
	data := text(tree, "cases.json")
	var total = 0
	var failing: List[String] = []

	for table in [
		"parse", "parse_errors", "resolve", "unescape", "query_escape", "path_escape",
		"query"
	]:
		items := cases(data, table)?

		for i in 0..items.length():
			total += 1
			if not check(table, i, items[i]): failing.append(f"{table}#{i}")

	failing.sort()

	var expected: List[String] = []
	var by_design = 0

	for line in text(tree, "expect-fail.txt").split("\n"):
		name := line.split(" ").get_or(0, "")
		if name != "" and not name.starts_with("#"): expected.append(name.clone())
		if line.contains(" by design:"): by_design += 1

	expected.sort()
	print(
		f"{total} cases, {expected.length()} not passing, {by_design} unsupported by design"
	)
	failing | expect_equal(expected)?
