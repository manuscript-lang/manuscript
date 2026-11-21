// References, highlights and rename over the occurrence index (index.ms). The Rust
// server answers the same requests in crates/ms-lsp/src/nav.rs and rename.rs: a
// reference is every occurrence with the selected key, a rename is refused unless the
// workspace checks before and after it, and a name already written in the file blocks
// the new spelling because it could capture another binding.
import (
	JsonValue from "@std/data/json.ms",
	expect_equal, expect_ok from "@std/test/test.ms",

	lex, token_kind from "../syntax.ms",
	Occurrence from "./index.ms",
	field, json_text, list, number, object from "./rpc.ms",
	range_json from "./text.ms",
)

// The occurrence the cursor is on: its range covers `offset`, the end excluded.
export fn occurrence_at(found: List[Occurrence], offset: Int) Occurrence?:
	for each in found:
		if offset >= each.start and offset < each.end: return each.clone()
	return none

fn same_entity(
	found: List[Occurrence],
	key: String,
	include_declaration: Bool,
) List[Occurrence]:
	var kept: List[Occurrence] = []

	for each in found:
		if each.key != key: continue
		if each.declaration and not include_declaration: continue

		kept.append(each.clone())

	return kept

// `Location`s of every occurrence of the name under `offset`.
export fn references(
	uri: String,
	text: String,
	found: List[Occurrence],
	offset: Int,
	include_declaration: Bool,
) JsonValue:
	selected := occurrence_at(found, offset)
	if selected.is_none(): return list([])

	var locations: List[JsonValue] = []
	for each in same_entity(found, selected.get().key, include_declaration):
		locations.append(
			object(
				[
					field("uri", json_text(uri)),
					field(
						"range",
						range_json(text, each.start, each.end),
					),
				]
			)
		)
	return list(locations)

// `DocumentHighlight`s of the name under `offset`; every one is a read.
export fn highlights(text: String, found: List[Occurrence], offset: Int) JsonValue:
	selected := occurrence_at(found, offset)
	if selected.is_none(): return list([])

	var marks: List[JsonValue] = []
	for each in same_entity(found, selected.get().key, true):
		marks.append(
			object(
				[
					field(
						"range",
						range_json(text, each.start, each.end),
					),
					field("kind", number(2)),
				]
			)
		)
	return list(marks)

fn is_standard(key: String) Bool: key.contains(":@std")

// Why the name under `offset` cannot be renamed, "" when it can.
fn refusal(found: List[Occurrence], selected: Occurrence) String:
	if is_standard(selected.key): return "standard-library declarations are read-only"
	if (
		selected.name == "main"
		and selected.key.starts_with("s:")
		and selected.key.ends_with(":main")
	):
		return "main is the program entry point; the run command looks it up by name"

	for each in found:
		if each.key == selected.key and each.declaration: return ""
	return "declaration is external or has no editable source"

// The range and name of the declaration that `offset` selects, or why it cannot be
// renamed.
export fn prepare_rename(
	text: String,
	found: List[Occurrence],
	offset: Int,
) Result[JsonValue, Error]:
	selected := occurrence_at(found, offset)
	if selected.is_none(): return error(
		Error("select a name that refers to a source declaration")
	)

	why := refusal(found, selected.get())
	if not why.is_empty(): return error(Error(why))

	return ok(
		object(
			[
				field(
					"range",
					range_json(
						text,
						selected.get().start,
						selected.get().end,
					),
				),
				field("placeholder", json_text(selected.get().name)),
			]
		)
	)

// Whether `name` is one identifier and not a keyword.
fn is_identifier(name: String) Bool:
	tokens := lex(name)
	if tokens.is_error(): return false

	// The lexer ends every text with a newline and an end token.
	words := tokens.get()
	return words.length() == 3 and words[0].kind == token_kind("NAME")

// Whether `name` is already written as an identifier in `text`.
fn written_in(text: String, name: String) Bool:
	tokens := lex(text)
	if tokens.is_error(): return false

	kind := token_kind("NAME")
	for word in tokens.get():
		if word.kind == kind and text.view(word.offset, word.end_offset) == name: return true
	return false

// `text` with the occurrences of the selected entity respelled as `name`.
export fn apply_rename(text: String, edits: List[Occurrence], name: String) String:
	var ordered = edits.clone()
	ordered.sort(latest_first)

	var result = text.clone()
	for each in ordered:
		result = result.view(0, each.start).concat(name).concat(
			result.view(each.end, result.length())
		)
	return result

fn latest_first(left: Occurrence, right: Occurrence) Int:
	if left.start != right.start: return if left.start > right.start: -1 else: 1
	return 0

// The edits that rename the name under `offset` to `name`: one document's worth of
// changes, or why the rename is refused. `before` and `after` are the diagnostics of
// the buffer before and with the edit applied, so the rename is only proposed when the
// result still checks.
export type Renamed:
	// The occurrences to respell, in source order.
	edits: List[Occurrence]
	// The buffer with the edits applied.
	updated: String

export fn plan_rename(
	text: String,
	found: List[Occurrence],
	offset: Int,
	name: String,
) Result[Renamed, Error]:
	selected := occurrence_at(found, offset)
	if selected.is_none(): return error(
		Error("select a name that refers to a source declaration")
	)

	why := refusal(found, selected.get())
	if not why.is_empty(): return error(Error(why))
	if not is_identifier(name): return error(
		Error("new name must be a Manuscript identifier")
	)
	if name != selected.get().name and written_in(text, name): return error(
		Error(
			f"{name} already occurs in this file; rename could capture another binding"
		)
	)

	edits := same_entity(found, selected.get().key, true)
	updated := apply_rename(text, edits, name)
	return ok(Renamed(edits: edits, updated: updated))

// The `WorkspaceEdit` for a planned rename of one open document.
export fn rename_edit(
	uri: String,
	version: Int,
	text: String,
	plan: Renamed,
	name: String,
) JsonValue:
	var edits: List[JsonValue] = []
	var ordered = plan.edits.clone()
	ordered.sort(latest_first)
	for each in ordered:
		edits.append(
			object(
				[
					field(
						"range",
						range_json(text, each.start, each.end),
					),
					field("newText", json_text(name)),
				]
			)
		)
	return object(
		[
			field(
				"documentChanges",
				list(
					[
						object(
							[
								field(
									"textDocument",
									object(
										[
											field(
												"uri",
												json_text(
													uri
												),
											),
											field(
												"version",
												number(
													version
												),
											),
										]
									),
								),
								field(
									"edits",
									list(edits),
								),
							]
						)
					]
				),
			)
		]
	)

fn occurrence(key: String, start: Int, declaration: Bool) Occurrence:
	return Occurrence(
		key: key,
		name: "x",
		start: start,
		end: start + 1,
		declaration: declaration,
	)

test "references keep the declaration only when asked":
	found := [
		occurrence("b:0", 4, true),
		occurrence("b:0", 10, false),
		occurrence("b:1", 7, true),
	]
	text := "let x = 1\nx + 1\nlet y"
	all := references("file:///a.ms", text, found, 10, true)
	expect_equal(all.as_list().get().length(), 2)?

	uses := references("file:///a.ms", text, found, 10, false)
	expect_equal(uses.as_list().get().length(), 1)?

	none_here := references("file:///a.ms", text, found, 0, true)
	expect_equal(none_here.as_list().get().length(), 0)?

test "highlights cover every occurrence of the name":
	found := [occurrence("b:0", 4, true), occurrence("b:0", 10, false)]
	marks := highlights("let x = 1\nx + 1", found, 4)
	expect_equal(marks.as_list().get().length(), 2)?

test "a new name must be an identifier that the file does not already write":
	found := [
		Occurrence(
			key: "b:0",
			name: "count",
			start: 0,
			end: 5,
			declaration: true,
		)
	]
	text := "count := other\n"
	expect_equal(plan_rename(text, found, 0, "two words").is_error(), true)?
	expect_equal(plan_rename(text, found, 0, "fn").is_error(), true)?
	expect_equal(plan_rename(text, found, 0, "other").is_error(), true)?

	plan := plan_rename(text, found, 0, "total") | expect_ok?
	expect_equal(plan.updated, "total := other\n")?

test "main, the standard library and undeclared names cannot be renamed":
	text := "main\n"
	entry := [
		Occurrence(
			key: "s:a.ms:main",
			name: "main",
			start: 0,
			end: 4,
			declaration: true,
		)
	]
	expect_equal(plan_rename(text, entry, 0, "start").is_error(), true)?

	library := [
		Occurrence(
			key: "s:@std:List",
			name: "List",
			start: 0,
			end: 4,
			declaration: false,
		)
	]
	expect_equal(prepare_rename("List\n", library, 0).is_error(), true)?

	external := [
		Occurrence(
			key: "s:b.ms:twice",
			name: "twice",
			start: 0,
			end: 5,
			declaration: false,
		)
	]
	expect_equal(prepare_rename("twice\n", external, 0).is_error(), true)?
	expect_equal(prepare_rename("twice\n", [], 0).is_error(), true)?
