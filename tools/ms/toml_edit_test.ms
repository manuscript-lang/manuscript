// Tests of the stdlib layout-preserving TOML document (`@std/data/toml.ms` `layout` and
// `@std/data/toml_edit.ms`) on generic documents; the manifest editor's own cases are in
// manifest_edit.ms.
import (
	TomlStatementKind, TomlValue, layout from "@std/data/toml.ms",
	parse_document, remove_key, set_key, to_string from "@std/data/toml_edit.ms",
	expect_equal from "@std/test/test.ms",
)

test "layout reports each statement's lines, keys and table":
	text := "# top\na = 1 # one\n\n[t.u]\nlist = [\n  1,\n  2,\n]\nx.y = \"z\"\n[[arr]]\nv = 1"
	read := layout(text)?
	expect_equal(read.statements.length(), 6)?

	first := read.statements[0]
	expect_equal(first.kind == TomlStatementKind.Pair, true)?
	expect_equal(first.keys, ["a"])?
	expect_equal(text.slice(first.start, first.end), "a = 1 # one\n")?

	header := read.statements[1]
	expect_equal(header.kind == TomlStatementKind.Header, true)?
	expect_equal(header.table, ["t", "u"])?

	multi := read.statements[2]
	expect_equal(multi.table, ["t", "u"])?
	expect_equal(text.slice(multi.start, multi.end), "list = [\n  1,\n  2,\n]\n")?

	dotted := read.statements[3]
	expect_equal(dotted.keys, ["x", "y"])?

	array := read.statements[4]
	expect_equal(array.kind == TomlStatementKind.ArrayHeader, true)?
	expect_equal(array.table, ["arr"])?

	last := read.statements[5]
	expect_equal(last.end, text.length())?

test "layout reads CRLF as LF and keeps offsets in that text":
	read := layout("a = 1\r\nb = 2\r\n")?
	expect_equal(read.text, "a = 1\nb = 2\n")?
	expect_equal(read.statements[1].start, 6)?

test "a set key replaces its line, a new key joins its table, a CRLF document stays CRLF":
	document := parse_document("[t]\r\n# keep\r\na = 1 # gone\r\n\r\n[u]\r\nb = 2\r\n")?
	replaced := set_key(document, ["t"], "a", TomlValue.IntValue(5))?
	expect_equal(to_string(replaced), "[t]\r\n# keep\r\na = 5\r\n\r\n[u]\r\nb = 2\r\n")?

	added := set_key(replaced, ["t"], "c", TomlValue.BoolValue(true))?
	expect_equal(
		to_string(added),
		"[t]\r\n# keep\r\na = 5\r\nc = true\r\n\r\n[u]\r\nb = 2\r\n",
	)?

	created := set_key(added, ["v", "w"], "d", TomlValue.StringValue("x"))?
	expect_equal(
		to_string(created),
		"[t]\r\n# keep\r\na = 5\r\nc = true\r\n\r\n[u]\r\nb = 2\r\n\r\n[v.w]\r\nd = \"x\"\r\n",
	)?

test "removing a key takes its comments and leaves no empty table":
	document := parse_document(
		"x = 1\n\n# about t\n[t]\n# about a\na = 1\n\n[u]\nb = 2\n"
	)?
	removed := remove_key(document, ["t"], "a")?
	expect_equal(to_string(removed), "x = 1\n\n[u]\nb = 2\n")?
	expect_equal(remove_key(document, ["t"], "zz").is_error(), true)?

test "a table written inline is refused for new keys and rebuilt for removals":
	document := parse_document("t = { a = 1, b = 2 }\n")?
	expect_equal(set_key(document, ["t"], "c", TomlValue.IntValue(3)).is_error(), true)?
	expect_equal(to_string(remove_key(document, ["t"], "a")?), "t = { b = 2 }\n")?

	only := parse_document("t = { a = 1 }\nu = 2\n")?
	expect_equal(to_string(remove_key(only, ["t"], "a")?), "u = 2\n")?
