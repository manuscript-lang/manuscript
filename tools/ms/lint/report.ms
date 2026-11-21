// The result of `ms lint` as the commands report it: the versioned `--json` document
// and the exit status. Both follow the Rust `ms lint`; `lint_diff.ms` and the corpus
// diff hold them to it.
import (
	Bytes from "@std/bytes.ms",
	JsonValue from "@std/data/json.ms",
	expect_equal from "@std/test/test.ms",

	list_of, number, object, render_document, text, with from "../json_out.ms",
	Finding, finding, with_fix from "./finding.ms",
)

// The version of the document.
FORMAT := 1

// The 1-based line and column of byte `offset` in `source`.
type Place:
	line: Int
	column: Int

fn place_of(source: Bytes, offset: Int) Place:
	var line = 1
	var start = 0

	for at in 0..offset:
		if source[at] == 10:
			line += 1
			start = at + 1

	return Place(line: line, column: offset - start + 1)

fn position(file: String, line: Int, column: Int, offset: Int) JsonValue:
	var at = object()
	at = with(at, "file", text(file))
	at = with(at, "line", number(line))
	at = with(at, "column", number(column))
	return with(at, "offset", number(offset))

// The `fix` member of a finding: where its edit starts and ends and what replaces it.
fn fix_json(found: Finding, source: Bytes) JsonValue:
	from := place_of(source, found.fix_from)
	to := place_of(source, found.fix_to)
	var fix = object()
	fix = with(
		fix,
		"position",
		position(found.file, from.line, from.column, found.fix_from),
	)
	fix = with(fix, "end", position(found.file, to.line, to.column, found.fix_to))
	return with(fix, "replacement", text(found.fix_text))

fn finding_json(found: Finding, source: Bytes) JsonValue:
	var entry = object()
	entry = with(entry, "code", text(found.code))
	entry = with(entry, "severity", text(found.severity))
	entry = with(entry, "message", text(found.message))
	entry = with(
		entry,
		"position",
		position(found.file, found.line, found.column, found.offset),
	)
	if found.fix_from >= 0: entry = with(entry, "fix", fix_json(found, source))
	return entry

// The `--json` document of `findings`; `sources` holds each file's text by path, which
// the fix positions are computed from.
export fn findings_document(findings: List[Finding], sources: Map[String, Bytes]) String:
	var entries = List[JsonValue]()
	for found in findings:
		entries.append(finding_json(found, sources.get_or(found.file, "".as_bytes())))

	var document = object()
	document = with(document, "format", number(FORMAT))
	return render_document(with(document, "diagnostics", list_of(entries)))

// 1 when a finding fails the run: an error, or any finding with `deny_warnings`.
export fn exit_status(findings: List[Finding], deny_warnings: Bool) Int:
	for found in findings:
		if deny_warnings or found.severity == "error": return 1
	return 0

test "a warning fails the run only when warnings are denied":
	warned := finding("MSL200", "warning", "m", "a.ms", 0, 1, 1)
	exit_status([warned.clone()], false) | expect_equal(expected: 0)?
	exit_status([warned.clone()], true) | expect_equal(expected: 1)?

	failed := finding("MSL122", "error", "m", "a.ms", 0, 1, 1)
	exit_status([failed.clone()], false) | expect_equal(expected: 1)?

test "no findings is an empty document":
	(
		findings_document([], Map[String, Bytes]()) | expect_equal(
			expected: "{\n  \"format\": 1,\n  \"diagnostics\": []\n}\n"
		)?
	)

test "a finding carries its position and its fix":
	source := "ab\ncd\n".as_bytes()
	found := with_fix(finding("MSL122", "error", "m", "a.ms", 4, 2, 2), 3, 5, "x")
	var sources = Map[String, Bytes]()
	sources.add("a.ms", source)

	document := findings_document([found], sources)
	document.contains("\"offset\": 4") | expect_equal(expected: true)?
	document.contains("\"replacement\": \"x\"") | expect_equal(expected: true)?
	(
		document.contains(
			"\"line\": 2,\n          \"column\": 1,\n          \"offset\": 3"
		)
		| expect_equal(expected: true)?
	)
