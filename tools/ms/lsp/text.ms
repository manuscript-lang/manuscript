// Positions as the editor sends them: a zero-based line and a UTF-16 character offset,
// against documents held as UTF-8 text. The server advertises `utf-16` position
// encoding, as crates/ms-lsp/src/text.rs does. A character offset past the end of its
// line stops at the line end; one inside a surrogate pair stops before the pair.
import (
	JsonValue from "@std/data/json.ms",
	expect_equal from "@std/test/test.ms",

	field, number, object from "./rpc.ms",
)

export type Position:
	line: Int
	character: Int

fn utf16_width(scalar: Int) Int:
	if scalar >= 65536: return 2
	return 1

// The length of `text` in UTF-16 units.
export fn utf16_length(text: String) Int:
	var units = 0
	for ch in text.chars():
		units += utf16_width(ch.scalar_at(0))
	return units

// The byte offset where line `line` starts, or the text length past the last line.
fn line_start(text: String, line: Int) Int:
	var offset = 0

	for step in 0..line:
		rest := text.view(offset, text.length())
		newline := rest.index_of("\n")
		if newline.is_none(): return text.length()

		offset += newline.get() + 1

	return offset

// The byte offset of `position` in `text`.
export fn offset_at(text: String, position: Position) Int:
	start := line_start(text, position.line)
	rest := text.view(start, text.length())
	newline := rest.index_of("\n")
	line := rest.view(0, newline.get_or(rest.length()))
	var units = 0
	var offset = start

	for ch in line.chars():
		width := utf16_width(ch.scalar_at(0))
		if units + width > position.character: break

		units += width
		offset += ch.length()

	return offset

// The position of byte `offset` in `text`, which must lie on a scalar boundary.
export fn position_at(text: String, offset: Int) Position:
	head := text.view(0, offset.min(text.length()))
	line := head.count("\n")
	start := line_start(text, line)
	var units = 0
	for ch in head.view(start, head.length()).chars():
		units += utf16_width(ch.scalar_at(0))
	return Position(line: line, character: units)

// An LSP position object for byte `offset`.
export fn position_json(text: String, offset: Int) JsonValue:
	at := position_at(text, offset)
	return object(
		[
			field("line", number(at.line)),
			field("character", number(at.character)),
		]
	)

// An LSP range object for the bytes from `start` to `end`.
export fn range_json(text: String, start: Int, end: Int) JsonValue:
	return object(
		[
			field("start", position_json(text, start)),
			field("end", position_json(text, end)),
		]
	)

// Replaces the bytes from `start` to `end` (positions) with `replacement`.
export fn replace_range(
	text: String,
	start: Position,
	end: Position,
	replacement: String,
) String:
	from := offset_at(text, start)
	to := offset_at(text, end).max(from)
	return text.view(0, from).concat(replacement).concat(text.view(to, text.length()))

test "offsets count UTF-16 units":
	text := "ab\n😀x\né"
	expect_equal(offset_at(text, Position(line: 0, character: 1)), 1)?
	expect_equal(offset_at(text, Position(line: 1, character: 2)), 7)?
	expect_equal(offset_at(text, Position(line: 1, character: 3)), 8)?
	expect_equal(offset_at(text, Position(line: 2, character: 1)), 11)?

test "a position past the line end stops at the line end":
	expect_equal(offset_at("ab\ncd", Position(line: 0, character: 9)), 2)?
	expect_equal(offset_at("ab\ncd", Position(line: 5, character: 0)), 5)?

test "a position inside a surrogate pair stays before it":
	expect_equal(offset_at("😀", Position(line: 0, character: 1)), 0)?

test "position_at inverts offset_at":
	text := "ab\n😀x\né"
	expect_equal(position_at(text, 8), Position(line: 1, character: 3))?
	expect_equal(position_at(text, 11), Position(line: 2, character: 1))?

test "replace_range edits across lines":
	expect_equal(
		replace_range(
			"ab\ncd\nef",
			Position(line: 0, character: 1),
			Position(line: 1, character: 1),
			"X",
		),
		"aXd\nef",
	)?

test "utf16_length counts surrogate pairs twice":
	expect_equal(utf16_length("a😀é"), 4)?
