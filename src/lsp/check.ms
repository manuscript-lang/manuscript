// Diagnostics for one open document. Until the C checker feeds facts straight to the
// server, the buffer is written beside its file under a hidden name, checked with
// `ms check --json` (so relative imports resolve) and removed again. The program is
// `$MS_RUST_CLI`, as in src/ms/main.ms, else `ms-rust`.
import (
	JsonValue, parse from "@std/data/json.ms",
	basename from "@std/os/path.ms",
	expect_equal from "@std/test/test.ms",

	Field, field, int_at, json_text, number, object, string_at from "./rpc.ms",
	run_on_scratch, scratch_name from "./scratch.ms",
	Position, position_at from "./text.ms",
)

fn is_word(ch: String) Bool:
	scalar := ch.scalar_at(0)
	return (
		(scalar >= 48 and scalar <= 57)
		or (scalar >= 65 and scalar <= 90)
		or scalar == 95
		or (scalar >= 97 and scalar <= 122)
		or scalar > 127
	)

// The byte offset where the word starting at `offset` ends; one scalar when it starts
// on punctuation, and `offset` itself at the end of the text.
export fn range_end_offset(source: String, offset: Int) Int:
	if offset >= source.length(): return source.length()

	var end = offset
	var first = true

	for ch in source.view(offset, source.length()).chars():
		if ch == "\n": break

		if not is_word(ch):
			if first: end += ch.length()
			break

		first = false
		end += ch.length()

	return end

fn diagnostic(source: String, issue: JsonValue) JsonValue:
	offset := int_at(issue, ["position", "offset"], 0)
	start := position_at(source, offset)
	end := position_at(source, range_end_offset(source, offset))
	code := string_at(issue, ["code"])
	var fields = [
		field(
			"range",
			object(
				[
					field(
						"start",
						object(
							[
								field(
									"line",
									number(
										start.line
									),
								),
								field(
									"character",
									number(
										start.character
									),
								),
							]
						),
					),
					field(
						"end",
						object(
							[
								field(
									"line",
									number(end.line),
								),
								field(
									"character",
									number(
										end.character
									),
								),
							]
						),
					),
				]
			),
		),
		field("severity", number(1)),
		field("source", json_text("manuscript")),
		field("message", json_text(string_at(issue, ["message"]))),
	]
	if not code.is_empty(): fields.append(field("code", json_text(code)))
	return object(fields)

// The LSP diagnostics in `report`, the output of `ms check --json`, for `source`.
// Only issues in the file named `file` count: the checker also reports imports.
export fn diagnostics_of(report: String, source: String, file: String) List[JsonValue]:
	var found: List[JsonValue] = []
	parsed := parse(report)
	if parsed.is_error(): return found

	document := parsed.get()
	issues := document.get("diagnostics").get_or(JsonValue.Null).as_list().get_or([])

	for issue in issues:
		if basename(string_at(issue, ["position", "file"])) != file: continue

		found.append(diagnostic(source, issue))

	return found

// Checks `source` as if it were the saved contents of `path`.
export fn check_document(path: String, source: String) List[JsonValue]:
	ran := run_on_scratch(path, source, ["check", "--json"])
	if ran.is_error(): return []

	return diagnostics_of(
		ran.get().output.stdout.decode_utf8().get_or(""),
		source,
		scratch_name(path),
	)

test "checker issues become LSP diagnostics":
	report := "{\"format\":1,\"diagnostics\":[{\"code\":\"MS2001\",\"phase\":\"resolution\",\"message\":\"unknown binding foo\",\"position\":{\"file\":\".ms-lsp-a.ms\",\"line\":2,\"column\":2,\"offset\":4}},{\"code\":\"MS1\",\"message\":\"elsewhere\",\"position\":{\"file\":\"other.ms\",\"line\":1,\"column\":1,\"offset\":0}}]}"
	found := diagnostics_of(report, "fn\n\tfoo()\n", ".ms-lsp-a.ms")
	expect_equal(found.length(), 1)?
	expect_equal(int_at(found[0], ["range", "start", "line"], -1), 1)?
	expect_equal(int_at(found[0], ["range", "start", "character"], -1), 1)?
	expect_equal(int_at(found[0], ["range", "end", "character"], -1), 4)?
	expect_equal(string_at(found[0], ["code"]), "MS2001")?

test "a range covers one word or one punctuation mark":
	expect_equal(range_end_offset("foo(bar)", 0), 3)?
	expect_equal(range_end_offset("foo(bar)", 3), 4)?
	expect_equal(range_end_offset("foo", 3), 3)?
