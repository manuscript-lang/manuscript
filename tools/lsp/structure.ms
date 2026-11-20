// The shape of a document read from its indentation: folding ranges and the outline.
// Neither needs the checker, so both work while the source has errors. The Rust server
// (crates/ms-lsp/src/features.rs, symbols.rs) takes folds from lexer suites and the
// outline from the checked module; this version follows the same rules by text and
// leaves the symbol detail (the checked type) empty.
import (
	JsonValue, stringify from "@std/data/json.ms",
	expect_equal from "@std/test/test.ms",

	field, json_text, list, number, object from "./rpc.ms",
	utf16_length from "./text.ms",
)

// Tabs count as four columns, as `ms_syntax::doc::indent_columns` does.
fn indent_of(line: String) Int:
	var columns = 0

	for ch in line.chars():
		if ch == " ": columns += 1
		else if ch == "\t": columns += 4
		else: break

	return columns

// `line` without a trailing `//` comment, whose slashes are not inside text.
fn code_of(line: String) String:
	var inside = false
	var escaped = false
	var offset = 0
	bytes := line.as_bytes()

	for ch in line.chars():
		if inside:
			if escaped: escaped = false
			else if ch == "\\": escaped = true
			else if ch == "\"": inside = false
		else if ch == "\"": inside = true
		else if (
			ch == "/"
			and offset + 1 < bytes.length()
			and bytes.get(offset + 1) == 47
		):
			return line.slice(0, offset)

		offset += ch.length()

	return line.clone()

fn lines_of(source: String) List[String]:
	var lines: List[String] = []
	for raw in source.split("\n"):
		lines.append(raw.cut_suffix("\r").get_or(raw))
	return lines

fn blank(line: String) Bool: line.trim().is_empty()

// Whether a line starts a suite: its last code character is a colon.
fn opens_suite(line: String) Bool: code_of(line).trim_end().ends_with(":")

// A fold for each suite header that has a deeper line after it, ending at the last
// non-blank line deeper than the header.
export fn folding_ranges(source: String) List[JsonValue]:
	lines := lines_of(source)
	var ranges: List[JsonValue] = []

	for start in 0..lines.length():
		if not opens_suite(lines[start]): continue

		level := indent_of(lines[start])
		var end = start

		for next in start + 1..lines.length():
			if blank(lines[next]): continue
			if indent_of(lines[next]) <= level: break

			end = next

		if end > start:
			ranges.append(
				object(
					[
						field("startLine", number(start)),
						field("endLine", number(end)),
						field("kind", json_text("region")),
					]
				)
			)

	return ranges

test "a suite folds to its last deeper line":
	found := folding_ranges(
		"fn a() Void:\n\tx := 1\n\n\treturn\n\nfn b() Void: ok()\nfn c() Void:\n\treturn\n"
	)
	expect_equal(found.length(), 2)?
	expect_equal(
		found[0],
		object(
			[
				field("startLine", number(0)),
				field("endLine", number(3)),
				field("kind", json_text("region")),
			]
		),
	)?
	expect_equal(
		found[1],
		object(
			[
				field("startLine", number(6)),
				field("endLine", number(7)),
				field("kind", json_text("region")),
			]
		),
	)?

test "a comment after the colon still opens a suite and a slash in text does not hide it":
	found := folding_ranges("if x: // go\n\ty()\nz := \"a//b:\"\n\tq\n")
	expect_equal(found.length(), 1)?

// ---- Outline ----

FUNCTION := 12
CONSTANT := 14
CLASS := 5
ENUM := 10
INTERFACE := 11
METHOD := 6
FIELD := 8
ENUM_MEMBER := 22

// One outline entry. `owner` is the index of the entry it is listed under, or -1.
type Symbol:
	name: String
	kind: Int
	owner: Int
	start_line: Int
	start_character: Int
	end_line: Int
	end_character: Int
	selection_line: Int
	selection_start: Int
	selection_end: Int

fn is_name_start(ch: String) Bool:
	scalar := ch.scalar_at(0)
	return (
		(scalar >= 65 and scalar <= 90)
		or scalar == 95
		or (scalar >= 97 and scalar <= 122)
	)

fn is_name_char(ch: String) Bool:
	scalar := ch.scalar_at(0)
	return is_name_start(ch) or (scalar >= 48 and scalar <= 57)

// The identifier at the start of `text`, or "".
fn name_at_start(text: String) String:
	var out = ""

	for ch in text.chars():
		if out.is_empty():
			if not is_name_start(ch): return ""
		else if not is_name_char(ch): break

		out = out.concat(ch)

	return out

fn drop_words(text: String, words: List[String]) String:
	var rest = text.clone()
	var changed = true

	while changed:
		changed = false

		for word in words:
			if cut := rest.cut_prefix(f"{word} "):
				rest = cut.trim_start()
				changed = true

	return rest

fn is_closer(line: String) Bool:
	return line.starts_with(")") or line.starts_with("]") or line.starts_with("}")

// The last non-blank line from `from` up to (not including) `until` that is part of a
// block: indented, or the header itself.
fn block_last(lines: List[String], from: Int, until: Int) Int:
	var last = from

	for index in from + 1..until:
		if blank(lines[index]): continue

		if indent_of(lines[index]) > 0 or is_closer(lines[index]): last = index

	return last

fn symbol_at(
	name: String,
	kind: Int,
	owner: Int,
	lines: List[String],
	line: Int,
	last: Int,
	search_from: Int,
) Symbol:
	text := lines[line]
	var column = 0
	if found := text.view(search_from, text.length()).index_of(name): column = (
		search_from
		+ found
	)

	selection_start := utf16_length(text.view(0, column))
	return Symbol(
		name: name.clone(),
		kind: kind,
		owner: owner,
		start_line: line,
		start_character: 0,
		end_line: last,
		end_character: utf16_length(lines[last].trim_end()),
		selection_line: line,
		selection_start: selection_start,
		selection_end: selection_start + utf16_length(name),
	)

// Fields, cases or interface methods listed under the declaration at `line`.
fn members(
	lines: List[String],
	line: Int,
	last: Int,
	owner: Int,
	kind: Int,
	var out: List[Symbol],
) Void:
	var level = -1

	for index in line + 1..last + 1:
		text := lines[index]
		if blank(text) or text.trim_start().starts_with("//") or is_closer(text): continue

		depth := indent_of(text)
		if level < 0: level = depth
		if depth != level: continue

		body := text.trim_start()
		column := text.length() - body.length()
		var name = ""
		var member_kind = kind

		if kind == INTERFACE:
			rest := drop_words(body, ["fn", "var", "move"])
			name = name_at_start(rest)
			member_kind = METHOD
		else if kind == ENUM:
			name = name_at_start(body)
			member_kind = ENUM_MEMBER
		else:
			head := name_at_start(body)
			if body.cut_prefix(head).get_or("").starts_with(":"): name = head
			member_kind = FIELD

		if name.is_empty(): continue

		var symbol = symbol_at(name, member_kind, owner, lines, index, index, column)
		symbol.end_character = utf16_length(text.trim_end())
		out.append(symbol)

fn json_position(line: Int, character: Int) JsonValue:
	return object([field("line", number(line)), field("character", number(character))])

fn json_range(
	start_line: Int,
	start_character: Int,
	end_line: Int,
	end_character: Int,
) JsonValue:
	return object(
		[
			field("start", json_position(start_line, start_character)),
			field("end", json_position(end_line, end_character)),
		]
	)

fn symbol_json(symbols: List[Symbol], index: Int) JsonValue:
	symbol := symbols[index]
	var children: List[JsonValue] = []
	for other in 0..symbols.length():
		if symbols[other].owner == index: children.append(symbol_json(symbols, other))

	var fields = [
		field("name", json_text(symbol.name)),
		field("detail", json_text("")),
		field("kind", number(symbol.kind)),
		field(
			"range",
			json_range(
				symbol.start_line,
				symbol.start_character,
				symbol.end_line,
				symbol.end_character,
			),
		),
		field(
			"selectionRange",
			json_range(
				symbol.selection_line,
				symbol.selection_start,
				symbol.selection_line,
				symbol.selection_end,
			),
		),
	]
	if not children.is_empty(): fields.append(field("children", list(children)))
	return object(fields)

// The hierarchical outline of `source`: declarations with their fields, cases and
// methods. A method of a type declared in the same file is listed under that type.
export fn document_symbols(source: String) List[JsonValue]:
	lines := lines_of(source)
	var symbols: List[Symbol] = []
	var declared = Map[String, Int]()
	var heads: List[Int] = []

	for index in 0..lines.length():
		text := lines[index]
		if (
			blank(text)
			or indent_of(text) > 0
			or text.starts_with("//")
			or is_closer(text)
		): continue

		heads.append(index)

	for position in 0..heads.length():
		line := heads[position]
		var until = lines.length()
		if position + 1 < heads.length(): until = heads[position + 1]

		last := block_last(lines, line, until)
		code := code_of(lines[line]).trim()
		rest := drop_words(code, ["export", "opaque", "extern"])
		var kind = 0
		var name = ""
		var type_name = ""

		if body := rest.cut_prefix("fn "):
			header := drop_words(body, ["var", "move"])
			name = name_at_start(header)

			after := header.cut_prefix(name).get_or("")

			if after.starts_with("."):
				type_name = name.clone()
				name = name_at_start(after.slice(1, after.length()))
				kind = METHOD
			else:
				kind = FUNCTION
		else if body := rest.cut_prefix("type "):
			kind = CLASS
			name = name_at_start(body)
		else if body := rest.cut_prefix("alias "):
			kind = CLASS
			name = name_at_start(body)
		else if body := rest.cut_prefix("enum "):
			kind = ENUM
			name = name_at_start(body)
		else if body := rest.cut_prefix("interface "):
			kind = INTERFACE
			name = name_at_start(body)
		else if body := rest.cut_prefix("test "):
			kind = FUNCTION
			name = f"test {body.cut_suffix(":").get_or(body).trim().trim_chars("\"")}"
		else if body := rest.cut_prefix("bench "):
			kind = FUNCTION
			name = f"bench {body.cut_suffix(":").get_or(body).trim().trim_chars("\"")}"
		else:
			head := name_at_start(rest)

			if (
				not head.is_empty()
				and rest.cut_prefix(head).get_or(
					""
				).trim_start().starts_with(":=")
			):
				kind = CONSTANT
				name = head

		if name.is_empty() or kind == 0: continue

		var owner = -1
		if declared.contains(type_name): owner = declared.get_or(type_name, -1)

		var shown = name.clone()
		if owner < 0 and not type_name.is_empty(): shown = f"{type_name}.{name}"

		index := symbols.length()
		var symbol = symbol_at(name, kind, owner, lines, line, last, 0)
		symbol.name = shown.clone()
		symbols.append(symbol)

		if kind == CLASS or kind == ENUM or kind == INTERFACE:
			declared.add(name.clone(), index)
			members(lines, line, last, index, kind, symbols)

	var out: List[JsonValue] = []
	for index in 0..symbols.length():
		if symbols[index].owner < 0: out.append(symbol_json(symbols, index))
	return out

fn stringify_all(values: List[JsonValue]) String: stringify(
	JsonValue.ArrayValue(values.clone())
).get_or("")

test "the outline lists declarations with their members and attaches methods to their type":
	source := "type P:\n\tx: Int\n\ty: Int\n\nenum E:\n\tA\n\tB(n: Int)\n\nfn P.get() Int:\n\treturn self.x\n\nfn main() Int:\n\treturn 1\n\nLIMIT := 3\n"
	found := document_symbols(source)
	expect_equal(found.length(), 4)?

	text := stringify_all(found)
	expect_equal(text.contains("\"name\":\"P\""), true)?
	expect_equal(text.contains("\"name\":\"x\",\"detail\":\"\",\"kind\":8"), true)?
	expect_equal(text.contains("\"name\":\"B\",\"detail\":\"\",\"kind\":22"), true)?
	expect_equal(text.contains("\"name\":\"get\",\"detail\":\"\",\"kind\":6"), true)?
	expect_equal(text.contains("\"name\":\"LIMIT\",\"detail\":\"\",\"kind\":14"), true)?
