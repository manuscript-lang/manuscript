// Configuration-oriented YAML 1.2 parser and writer implemented in Manuscript. Use
// `parse` for one document and `parse_all` for a stream.
//
// Mapping keys are strings. A scalar key (a number, boolean or null spelling, a quoted
// string, an empty key, or an alias to a scalar) becomes the text of that scalar, so
// `1` and `"1"` in one mapping are a duplicate key, which is an error. A sequence or
// mapping used as a key is rejected with an error that names its position.
//
// Tags other than `!` and `!!str` are read and ignored. Those two make a scalar a
// string, whatever its spelling.
import (
	Bytes from "@std/bytes.ms",
	panic from "@std/core.ms",
	quote_text from "@std/data/quote.ms",
	parse_int from "@std/math/math.ms",
	from_scalars from "@std/string.ms",
)

// A YAML value represented as null, boolean, number text, string, array, or object.
export enum YamlValue:
	// YAML null, including an empty document or a plain null spelling.
	Null
	// A core-schema true or false value; yes and no remain strings.
	BoolValue(
		// The decoded boolean selected from YAML core-schema spellings.
		value Bool
	)
	// Numeric token text retained exactly instead of being coerced into Float.
	NumberValue(
		// Original numeric spelling, including supported base prefixes and nonfinite
		// spellings.
		text String
	)
	// Text decoded from a quoted, plain or block scalar.
	StringValue(
		// Resulting Unicode text after escape decoding, folding and chomping.
		value String
	)
	// An ordered YAML sequence with ordinary mutable list storage.
	ArrayValue(
		// Sequence entries in document order, retaining nested references.
		values List[YamlValue]
	)
	// A textual-key mapping, with insertion order and duplicate-key checks.
	ObjectValue(
		// Decoded string keys and their values; aliases may share nested payloads.
		values Map[String, YamlValue]
	)

// Limits for `parse` and `parse_all` on input bytes, nesting depth and parsed values.
// A limit set to null adds no limit. The defaults, depth 10,000 and 1,000,000 values,
// guard against deep nesting and alias expansion. A negative limit returns `EINVAL`,
// and a document that exceeds one returns `EOVERFLOW`.
export type YamlOptions:
	// Maximum UTF-8 input bytes before line-ending normalization; null adds no budget.
	max_bytes Int? = null
	// Maximum value depth, including scalar leaves, with the root at one.
	max_depth Int? = 10000
	// Maximum containers and leaves, excluding keys; aliases count at each checked
	// occurrence.
	max_values Int? = 1000000

type Context:
	lines List[String]
	final_break Bool
	index Int
	values Int
	anchors Map[String, YamlValue]
	sizes Map[String, Int]
	/*
    Per-line facts computed once from the document bytes. A simple line is ASCII with no
    control character (so no tab), quote, bracket, brace or `#`, no trailing space and no
    leading `?`, so its comment-free text, indentation and mapping colon need no
    character-by-character scan. `blank` marks lines of spaces only, `dash` marks simple
    lines that start a sequence entry, `ind` is the indentation, and `col` is the offset of
    the mapping colon (-1 for null).
    */
	simple List[Bool]
	blank List[Bool]
	dash List[Bool]
	ind List[Int]
	col List[Int]
	max_depth Int?
	max_values Int?
	// Prefixes declared by %TAG directives, keyed by handle (`!`, `!!`, `!name!`).
	tag_handles Map[String, String] = Map[String, String]()
	// Whether the document just read ended with an explicit `...` marker.
	explicit_end Bool = false
	// Whether the document just read had no `---` marker and no content: no document at
	// all.
	absent_document Bool = false
	// Diagnostic projection for virtual lines (a line rewritten or split during
	// parsing): these shift reported line and column numbers back to the source;
	// parsing continues to use the same bases.
	split_line Int = -1
	shift_row Int = -1
	shift_column Int = 0

type SourcePosition:
	line Int
	column Int

type Flow:
	chars List[String]
	codes List[Int]
	pos Int
	line Int
	context Context
	delimited Bool
	column Int = 1
	// Scalar offsets where stripped comments terminate an already-started plain leaf.
	stops List[Int] = []
	next_stop Int = 0
	// A `!!str` or `!` tag on the next plain leaf keeps its text a string.
	force_string Bool = false

// YAML separates tokens with only space and tab; Unicode spaces such as U+00A0 are
// scalar content.
fn blank(code Int) Bool:
	return code == 32 or code == 9

// `text` without leading spaces and tabs.
fn blank_trim_start(text String) String:
	count := text.length()
	var from = 0
	while from < count and blank(text.scalar_at(from, default: 0)):
		from += 1
	if from == 0: return text.clone()

	return text.slice(from, count)

// `text` without trailing spaces and tabs.
fn blank_trim_end(text String) String:
	var end = text.length()
	while end > 0 and blank(text.scalar_at(end - 1, default: 0)):
		end -= 1
	if end == text.length(): return text.clone()

	return text.slice(0, end)

// `text` without leading and trailing spaces and tabs.
fn blank_trim(text String) String:
	return blank_trim_end(blank_trim_start(text))

fn within(value Int, limit Int?) Bool:
	maximum := limit
	if maximum != null: return value <= maximum

	return true

// Number of containers and leaves in a value, excluding keys.
fn tree_size(value YamlValue) Int:
	var total = 1

	match value:
		ArrayValue(values):
			for item in values: total += tree_size(item)
		ObjectValue(values):
			for entry in values: total += tree_size(entry.value.clone())
		_: void

	return total

// Records an anchor and the size of its value so aliases can be charged before they are
// copied.
fn define_anchor(var context Context, name String, value YamlValue) Void:
	context.anchors.add(name.clone(), value.clone())
	context.sizes.add(name.clone(), tree_size(value))

// Counts an alias expansion against the value budget before the aliased value is
// copied, so nested aliases cannot grow exponentially ahead of the limit.
fn charge(var context Context, size Int) Void!:
	context.values += size
	if not within(context.values, context.max_values): return error(
		Error("YAML limit exceeded", kind: "EOVERFLOW")
	)

fn count(var context Context, depth Int) Void!:
	if not within(depth, context.max_depth): return error(
		Error("YAML limit exceeded", kind: "EOVERFLOW")
	)

	context.values += 1
	if not within(context.values, context.max_values): return error(
		Error("YAML limit exceeded", kind: "EOVERFLOW")
	)

fn source_line(context Context, row Int) Int:
	if context.split_line >= 0 and row > context.split_line: return row
	return row + 1

fn source_column(context Context, row Int, column Int) Int:
	var result = column
	if context.split_line >= 0 and row == context.split_line + 1: result += 4
	if row == context.shift_row: result += context.shift_column
	return result

// A malformed-input error at a one-based source position.
fn yaml_invalid(line Int, column Int, reason String) Error:
	return Error(
		f"YAML {line}:{column}: {reason}",
		kind: "EBADMSG",
		details: {
			"line": line.to_string(),
			"column": column.to_string(),
			"reason": reason.clone()
		},
	)

// An error for syntax this configuration parser does not support.
fn yaml_unsupported(line Int, reason String) Error:
	return Error(
		f"YAML {line}: {reason}",
		kind: "ENOTSUP",
		details: {"line": line.to_string(), "reason": reason.clone()},
	)

fn invalid(context Context, reason String) Error:
	return yaml_invalid(
		line: source_line(context, context.index),
		column: source_column(context, context.index, 1),
		reason: reason,
	)

fn peek(flow Flow) String:
	return flow.chars.get_or(flow.pos, "").clone()

fn advance(var flow Flow) String:
	c := peek(flow)
	if c != "": flow.pos += 1
	return c.clone()

// The scalar value at the cursor, or 0 at the end; `codes` is empty for flows that only
// read quoted text.
fn cur(flow Flow) Int:
	return flow.codes.get_or(flow.pos, 0)

fn step(var flow Flow) Int:
	code := cur(flow)
	if code != 0: flow.pos += 1
	return code

fn flow_space(var flow Flow) Void:
	while true:
		code := cur(flow)
		if code != 32 and code != 9 and code != 10: break

		flow.pos += 1

// The source line and column of scalar offset `cursor` in `chars`, which starts at
// `line` and `column`. Called only to build errors, so valid input needs no position
// scan.
fn cursor_position(chars List[String], cursor Int, line Int, column Int) SourcePosition:
	var breaks = 0
	var width = 0
	var at = 0

	while at < cursor and at < chars.length():
		if chars[at] == "\n":
			breaks += 1
			width = 0
		else: width += 1

		at += 1

	return SourcePosition(
		line: line + breaks,
		column: if breaks == 0: column + width else: width + 1,
	)

fn flow_position(flow Flow, cursor Int) SourcePosition:
	return cursor_position(flow.chars, cursor, flow.line, flow.column)

fn flow_invalid(flow Flow, reason String, cursor Int = -1) Error:
	position := flow_position(flow, if cursor < 0: flow.pos else: cursor)
	return yaml_invalid(line: position.line, column: position.column, reason: reason)

// Reads the empty lines after a line break inside a quoted scalar, whose first break
// has been consumed. With no empty lines the break folds to one space; with empty lines
// each becomes a newline and the first break adds nothing. An escaped break adds
// nothing even when no empty lines follow it.
fn folded_break(var flow Flow, escaped Bool) String:
	var result = ""

	while true:
		while peek(flow) == " " or peek(flow) == "\t": advance(flow)
		if peek(flow) != "\n": break

		advance(flow)
		result = result.concat("\n")

	if result == "" and not escaped: return " "

	return result

fn quoted(var flow Flow) String!:
	quote := advance(flow)

	// Append through a builder: per-character concatenation is quadratic on long
	// strings.
	var result = ""
	var whitespace = ""

	while true:
		c := advance(flow)
		if c == "": return error(flow_invalid(flow, "unterminated string"))

		if c == quote:
			result += whitespace
			whitespace = ""

			if quote == "'" and peek(flow) == "'":
				advance(flow)
				result += "'"
				continue

			return ok(result)

		if c == "\n":
			whitespace = ""
			result += folded_break(flow, escaped: false)
			continue

		if c == " " or c == "\t":
			whitespace += c
			continue

		result += whitespace
		whitespace = ""

		if c != "\\" or quote == "'":
			result += c
			continue

		escaped := advance(flow)

		if escaped == "\n":
			result += folded_break(flow, escaped: true)
		else if escaped == "0": result += "\u{0}"
		else if escaped == "a": result += "\u{7}"
		else if escaped == "b": result += "\u{8}"
		else if escaped == "t" or escaped == "\t": result += "\t"
		else if escaped == "n": result += "\n"
		else if escaped == "v": result += "\u{b}"
		else if escaped == "f": result += "\u{c}"
		else if escaped == "r": result += "\r"
		else if escaped == "e": result += "\u{1b}"
		else if (escaped == " " or escaped == "\"" or escaped == "/" or escaped == "\\"): result += escaped
		else if escaped == "N": result += "\u{85}"
		else if escaped == "_": result += "\u{a0}"
		else if escaped == "L": result += "\u{2028}"
		else if escaped == "P": result += "\u{2029}"
		else if (escaped == "x" or escaped == "u" or escaped == "U"):
			var count = 2
			if escaped == "u": count = 4
			if escaped == "U": count = 8

			var hex = ""

			while count > 0:
				digit := advance(flow)
				if digit == "" or not "0123456789abcdefABCDEF".contains(digit): return error(
					flow_invalid(flow, "invalid Unicode escape")
				)

				hex = hex.concat(digit)
				count -= 1

			parsed := parse_int(hex, 16)
			if parsed.is_error(): return error(
				flow_invalid(flow, "invalid Unicode escape")
			)

			if text := from_scalars([parsed.get()]):
				result += text
			else:
				return error(flow_invalid(flow, "invalid Unicode scalar"))
		else:
			return error(flow_invalid(flow, "invalid string escape"))

// The byte offset of the scalar at position `index` of `text`; the length when the
// position is past the end. The parser counts source columns in scalars and slices text
// by bytes.
fn byte_at_scalar(text String, index Int) Int:
	var at = 0
	var seen = 0

	for c in text.chars():
		if seen == index: break

		at += c.length()
		seen += 1

	return at

fn digit_text(text String) Bool:
	if text == "": return false

	for code in text.scalar_values():
		if code < 48 or code > 57: return false
	return true

fn numeric(text String) Bool:
	first := text.scalar_at(0, default: 0)
	if not (first == 43 or first == 45 or first == 46 or (first >= 48 and first <= 57)): return false

	var clean = text.clone()
	if clean.starts_with("+") or clean.starts_with("-"): clean = clean.slice(
		1,
		clean.length(),
	)
	if (clean == ".inf" or clean == ".Inf" or clean == ".INF"): return true
	if (text == ".nan" or text == ".NaN" or text == ".NAN"): return true

	if clean.starts_with("0x") or clean.starts_with("0o"):
		if clean != text: return false

		alphabet := if clean.starts_with("0x"): "0123456789abcdefABCDEF" else: "01234567"
		digits := clean.slice(2, clean.length())
		if digits == "": return false

		for c in digits.split(""):
			if not alphabet.contains(c): return false
		return true

	exponent := clean.lower().split("e")
	if exponent.length() > 2: return false

	if exponent.length() == 2:
		var power = (exponent.last() or panic("called Optional.get() on null")).clone()
		if power.starts_with("+") or power.starts_with("-"): power = power.slice(
			1,
			power.length(),
		)
		if not digit_text(power): return false

	mantissa := (exponent.first() or panic("called Optional.get() on null")).split(".")
	if mantissa.length() > 2: return false
	if mantissa.length() == 1: return digit_text(
		mantissa.first() or panic("called Optional.get() on null")
	)

	whole := mantissa.first() or panic("called Optional.get() on null")
	fraction := mantissa.last() or panic("called Optional.get() on null")
	if whole == "" and fraction == "": return false

	return (
		(whole == "" or digit_text(whole))
		and (fraction == "" or digit_text(fraction))
	)

fn plain(text String) YamlValue:
	if (text == "" or text == "~" or text == "null" or text == "Null" or text == "NULL"): return YamlValue.Null
	if (text == "true" or text == "True" or text == "TRUE"): return YamlValue.BoolValue(
		true
	)
	if (text == "false" or text == "False" or text == "FALSE"): return YamlValue.BoolValue(
		false
	)
	if numeric(text.clone()): return YamlValue.NumberValue(text.clone())

	return YamlValue.StringValue(text.clone())

fn anchor_name(var flow Flow) String!:
	var name = ""
	while peek(flow) != "" and not " \t\n,[]{}".contains(peek(flow)):
		name = name.concat(advance(flow))
	if name == "": return error(flow_invalid(flow, "empty anchor name"))

	return ok(name)

// The resolved tag at the cursor, which sits on `!`: a verbatim `!<uri>`, `!!name` (the
// core schema unless a `%TAG` directive redeclares `!!`), `!handle!name` for a declared
// handle, `!` alone (the non-specific tag), or a local `!name`.
fn tag_token(var flow Flow) String!:
	advance(flow)

	if peek(flow) == "<":
		advance(flow)

		var uri = ""
		while (
			peek(flow) != ""
			and peek(flow) != ">"
			and not " \t\n".contains(peek(flow))
		):
			uri = uri.concat(advance(flow))
		if peek(flow) != ">": return error(
			flow_invalid(flow, "unterminated verbatim tag")
		)

		advance(flow)
		if uri == "": return error(flow_invalid(flow, "empty verbatim tag"))

		return ok(uri)

	var name = ""
	while peek(flow) != "" and not " \t\n,[]{}".contains(peek(flow)):
		name = name.concat(advance(flow))

	handles := flow.context.tag_handles

	// `!!name` and `!handle!name` expand through the declared prefixes.
	if name.starts_with("!"):
		var prefix = "tag:yaml.org,2002:"
		declared := handles.get("!!")
		if declared != null: prefix = declared.clone()
		return ok(f"{prefix}{name.slice(1, name.length())}")

	bang := name.index_of("!")

	if bang != null:
		handle := f"!{name.slice(0, bang + 1)}"
		prefix := handles.get(handle)
		if prefix != null: return ok(f"{prefix}{name.slice(bang + 1, name.length())}")

		return error(flow_invalid(flow, "undeclared tag handle"))

	if name != "":
		prefix := handles.get("!")
		if prefix != null: return ok(f"{prefix}{name}")

	return ok(f"!{name}")

// The mapping key a scalar node stands for: its text. A collection cannot be a key.
fn key_text(value YamlValue) String?:
	match value:
		StringValue(text): return text.clone()
		NumberValue(text): return text.clone()
		BoolValue(flag):
			if flag: return "true"
			return "false"
		Null: return "null"
		_: return null

// Whether a tag makes a scalar a string whatever its spelling.
fn string_tag(tag String) Bool:
	return tag == "!" or tag == "tag:yaml.org,2002:str"

fn merge(line Int, column Int, var target Map[String, YamlValue], value YamlValue) Void!:
	values := match value:
		ObjectValue(entries):
			for entry in entries:
				if not target.contains(entry.key): target.add(
					entry.key.clone(),
					entry.value.clone(),
				)
			return ok()
		ArrayValue(values): values
		_: return error(
			yaml_invalid(
				line: line,
				column: column,
				reason: "merge requires mappings",
			)
		)

	for item in values:
		match item:
			ObjectValue(_): merge(
				line: line,
				column: column,
				target: target,
				value: item,
			)?
			_: return error(
				yaml_invalid(
					line: line,
					column: column,
					reason: "merge requires mappings",
				)
			)

	return ok()

// Folds a plain scalar that continues across lines: a single line break becomes one
// space, and each blank line becomes a newline.
fn fold_plain(text String) String:
	if not text.contains("\n"): return text.clone()

	var result = ""
	var blanks = 0
	var first = true

	for line in text.split("\n"):
		trimmed := blank_trim(line)

		if trimmed == "":
			blanks += 1
			continue

		if first: result += trimmed
		else if blanks == 0:
			result += " "
			result += trimmed
		else:
			var remaining = blanks

			while remaining > 0:
				result += "\n"
				remaining -= 1

			result += trimmed

		blanks = 0
		first = false

	return result

// Whether the character following a colon ends a plain scalar in this context.
fn separates_colon(next Int, delimited Bool) Bool:
	if next == 0 or next == 9 or next == 10 or next == 32: return true
	return (
		delimited
		and (
			next == 44
			or next == 91
			or next == 93
			or next == 123
			or next == 125
		)
	)

// The text of the key of a one-entry mapping inside a flow sequence. An implicit key
// must stay on one line from offset `from` to the cursor.
fn pair_key_text(flow Flow, key YamlValue, from Int, empty Bool) String!:
	var row = from

	while row < flow.pos:
		if flow.codes[row] == 10: return error(
			flow_invalid(
				flow,
				"an implicit mapping key must stay on one line",
			)
		)

		row += 1

	if empty: return ok("")

	scalar := key_text(key)
	if scalar == null: return error(
		yaml_unsupported(
			line: flow_position(flow, flow.pos).line,
			reason: "mapping keys must be scalars, not a collection",
		)
	)

	return ok(scalar)

// Whether the cursor sits on a flow `?` that opens an explicit key.
fn explicit_start(flow Flow) Bool:
	return (
		cur(flow) == 63
		and separates_colon(flow.codes.get_or(flow.pos + 1, 0), true)
	)

// A one-entry mapping from `key` to null.
fn null_pair(key String) YamlValue:
	var only = Map[String, YamlValue]()
	only.add(key.clone(), YamlValue.Null)
	return YamlValue.ObjectValue(only)

// A scalar, alias or quoted string at the cursor, whose first code is `c`.
fn flow_leaf(var flow Flow, c Int, key Bool, pair Bool = false) YamlValue!:
	if c == 42:
		advance(flow)

		name := anchor_name(flow)?
		size := flow.context.sizes.get(name)
		if size != null:
			charge(flow.context, size)?

		value := flow.context.anchors.get(name)
		if value != null: return ok(value.clone())

		return error(flow_invalid(flow, "unknown or recursive alias"))

	if c == 34 or c == 39: return ok(YamlValue.StringValue(quoted(flow)?))
	if c == 35: return error(
		flow_invalid(flow, "a comment needs whitespace before its hash")
	)

	start := flow.pos
	while (flow.next_stop < flow.stops.length() and flow.stops[flow.next_stop] <= start): flow.next_stop += 1

	stop := flow.stops.get_or(flow.next_stop, flow.chars.length())

	while flow.pos < stop:
		code := cur(flow)
		if code == 0: break
		if (
			(flow.delimited or key)
			and (
				code == 44
				or code == 91
				or code == 93
				or code == 123
				or code == 125
			)
		): break

		if (
			code == 58
			and separates_colon(
				flow.codes.get_or(flow.pos + 1, 0),
				flow.delimited or key,
			)
		):
			if key or pair: break
			return error(flow_invalid(flow, "unexpected mapping colon"))

		flow.pos += 1

	// Slice once: appending each character to a string is quadratic on long scalars.
	var text = blank_trim(flow.chars.slice(start, flow.pos).clone().get_or([]).join(""))
	if (
		text.starts_with("?")
		and (text.length() == 1 or " \t".contains(text.chars()[1]))
	): return error(
		yaml_unsupported(
			line: flow_position(flow, start).line,
			reason: "explicit mapping keys are unsupported",
		)
	)
	if not (plain_may_start(text) or key and text == "-"): return error(
		flow_invalid(
			flow,
			"a plain scalar cannot start with an indicator character",
		)
	)

	if flow.delimited: text = fold_plain(text)
	if key or flow.force_string: return ok(YamlValue.StringValue(text))

	return ok(plain(text))

// Stores a finished mapping value under `name`.
fn flow_entry(
	var flow Flow,
	name String,
	quoted_key Bool,
	var entries Map[String, YamlValue],
	var explicit Set[String],
	value YamlValue,
) Void!:
	if explicit.contains(name): return error(
		flow_invalid(flow, "duplicate mapping key")
	)

	explicit.add(name.clone())

	if name == "<<" and not quoted_key:
		cause := match merge(
			line: flow.line,
			column: flow.pos + 1,
			target: entries,
			value: value,
		):
			ok(_): return ok()
			error(cause): cause

		if cause.kind != "EBADMSG": return error(cause)

		reason := cause.details.get_or("reason", "").clone()

		// A plain value may have consumed trailing separation before the delimiter.
		// Point this value-type error at its end, rather than a later closing line.
		end := flow.pos
		var trailing = 0

		while end - trailing > 0:
			code := flow.codes[end - trailing - 1]
			if code != 32 and code != 9 and code != 10: break

			trailing += 1

		return error(flow_invalid(flow, reason, cursor: end - trailing))
	else:
		entries.add(name.clone(), value.clone())

	return ok()

// A flow container suspended while its child is read.
type FlowFrame:
	kind Int = 0
	level Int = 0
	anchors List[String] = []
	items List[YamlValue] = []
	entries Map[String, YamlValue] = Map[String, YamlValue]()
	explicit Set[String] = Set[String]()
	name String = ""
	quoted_key Bool = false
	single Bool = false

/*
Parses a flow value. Nested sequences and mappings use explicit stacks instead of recursion,
so the depth limit, not the call stack, bounds nesting. Only a mapping key recurses, and a
key cannot be a container.
*/
fn flow_value(var flow Flow, depth Int, key Bool) YamlValue!:
	// The suspended parent containers, innermost last, each with its kind (1 sequence,
	// 2 mapping), depth, anchors and entries so far. The innermost open container is
	// held in the variables below, not in `frames`.
	var frames List[FlowFrame] = []

	// kind 0 is the request itself, before any container opens.
	var kind = 0
	var level = depth
	var anchors List[String] = []
	var items List[YamlValue] = []
	var entries = Map[String, YamlValue]()
	var explicit = Set[String]()
	var name = ""
	var quoted_key = false

	// A mapping opened by `key: value` inside a sequence holds that one entry.
	var single = false
	var empty_key = false
	var explicit_pair = false
	var leaf_start = 0
	var phase = 0
	var done = YamlValue.Null
	var child_key = key

	// Phase 0 begins a value inside the innermost container, phase 1 hands it a
	// finished value, and phase 2 reads what follows the opening bracket or a comma.
	while true:
		if phase == 0:
			child_depth := if kind == 0: depth else: level + 1
			var written List[String] = []
			var is_key = child_key
			var as_string = flow.force_string
			child_key = false
			flow.force_string = false

			while true:
				flow_space(flow)
				if not is_key:
					count(flow.context, child_depth)?

				if cur(flow) == 33:
					tag := tag_token(flow)?
					as_string = as_string or string_tag(tag)
					flow.context.values -= 1
					continue

				// `? key` inside a sequence opens a one-entry mapping with that key.
				if (
					kind == 1
					and not is_key
					and not explicit_pair
					and explicit_start(flow)
				):
					advance(flow)
					explicit_pair = true
					continue

				if cur(flow) != 38: break

				advance(flow)

				anchor := anchor_name(flow)?
				flow.context.values -= 1
				written.append(anchor)

			c := cur(flow)
			if c == 42 and not written.is_empty(): return error(
				flow_invalid(flow, "an alias cannot have an anchor")
			)

			if c == 91 or c == 123:
				flow.delimited = true
				if is_key or explicit_pair: return error(
					yaml_unsupported(
						line: flow_position(
							flow,
							flow.pos,
						).line,
						reason: "mapping keys must be scalars, not a collection",
					)
				)

				advance(flow)
				flow_space(flow)
				frames.append(
					FlowFrame(
						kind: kind,
						level: level,
						anchors: anchors,
						items: items,
						entries: entries,
						explicit: explicit,
						name: name,
						quoted_key: quoted_key,
						single: single,
					)
				)
				single = false
				kind = if c == 91: 1 else: 2
				level = child_depth
				anchors = written
				items = []
				entries = Map[String, YamlValue]()
				explicit = Set[String]()
				name = ""
				quoted_key = false
				phase = 2
				continue

			flow.force_string = as_string
			leaf_start = flow.pos

			leaf := flow_leaf(flow, c, is_key, pair: kind == 1)?
			empty_key = c == 58 or (explicit_pair and (c == 44 or c == 93))
			flow.force_string = false
			for anchor in written.reversed():
				define_anchor(flow.context, anchor, leaf.clone())
			done = leaf
			phase = 1
			continue

		if phase == 1:
			if kind == 0: return ok(done)

			if kind == 1:
				flow_space(flow)

				// `key: value` inside a sequence is a one-entry mapping.
				colon := cur(flow) == 58

				if colon or explicit_pair:
					// An explicit `?` key may span lines; an implicit one may not.
					pair_key := pair_key_text(
						flow,
						done,
						from: if explicit_pair: flow.pos else: leaf_start,
						empty: empty_key,
					)?
					empty_key = false
					explicit_pair = false

					// `? key` with no colon maps the key to null.
					if not colon:
						count(flow.context, level + 1)?
						items.append(null_pair(pair_key))

						if cur(flow) != 93:
							if step(flow) != 44: return error(
								flow_invalid(
									flow,
									"expected sequence comma",
								)
							)

							flow_space(flow)

						phase = 2
						continue

					advance(flow)
					flow_space(flow)
					count(flow.context, level + 1)?
					frames.append(
						FlowFrame(
							kind: kind,
							level: level,
							anchors: anchors,
							items: items,
							entries: entries,
							explicit: explicit,
							name: name,
							quoted_key: quoted_key,
							single: single,
						)
					)
					kind = 2
					level += 1
					anchors = []
					items = []
					entries = Map[String, YamlValue]()
					explicit = Set[String]()
					name = pair_key
					quoted_key = false
					single = true
					phase = 0
					continue

				items.append(done)
				done = YamlValue.Null

				if cur(flow) != 93:
					if step(flow) != 44: return error(
						flow_invalid(
							flow,
							"expected sequence comma",
						)
					)

					flow_space(flow)
					phase = 2
					continue
			else:
				flow_entry(flow, name, quoted_key, entries, explicit, done)?
				done = YamlValue.Null

				if single:
					done = YamlValue.ObjectValue(entries)

					parent := frames.pop() or FlowFrame()
					kind = parent.kind
					level = parent.level
					anchors = parent.anchors
					items = parent.items
					entries = parent.entries
					explicit = parent.explicit
					name = parent.name
					quoted_key = parent.quoted_key
					single = parent.single
					continue

				flow_space(flow)

				if cur(flow) != 125:
					if step(flow) != 44: return error(
						flow_invalid(
							flow,
							"expected mapping comma",
						)
					)

					flow_space(flow)
					phase = 2
					continue

		// Phase 2 may close the container too; both end here with the closing bracket
		// at the cursor.
		if phase == 2:
			if kind == 1:
				if cur(flow) != 93:
					if cur(flow) == 0 or cur(flow) == 44: return error(
						flow_invalid(
							flow,
							"expected flow sequence value",
						)
					)

					phase = 0
					continue
			else if cur(flow) != 125:
				if cur(flow) == 0: return error(
					flow_invalid(flow, "unterminated flow mapping")
				)
				if cur(flow) == 44: return error(
					flow_invalid(flow, "expected flow mapping key")
				)

				// `? key` is an explicit entry, and a bare `?` before a delimiter is empty.
				if explicit_start(flow):
					advance(flow)
					flow_space(flow)

					if cur(flow) == 44 or cur(flow) == 125:
						name = ""
						quoted_key = false
						count(flow.context, level + 1)?
						done = YamlValue.Null
						phase = 1
						continue

				quoted_key = cur(flow) == 34 or cur(flow) == 39

				key_start := flow.pos
				parsed_key := flow_value(flow, level, key: true)?
				_key_end := flow.pos
				flow_key := key_text(parsed_key)
				if flow_key == null: return error(
					yaml_unsupported(
						line: flow_position(
							flow,
							key_start,
						).line,
						reason: "mapping keys must be scalars, not a collection",
					)
				)

				name = flow_key
				flow_space(flow)

				// A key with no colon, as in `{a, b: 1}`, maps to null.
				if cur(flow) == 44 or cur(flow) == 125:
					count(flow.context, level + 1)?
					done = YamlValue.Null
					phase = 1
					continue

				if step(flow) != 58: return error(
					flow_invalid(flow, "expected mapping colon")
				)

				phase = 0
				continue

		// The closing bracket is at the cursor: the innermost container is complete.
		advance(flow)

		if kind == 1: done = YamlValue.ArrayValue(items)
		else: done = YamlValue.ObjectValue(entries)

		for anchor in anchors.reversed():
			define_anchor(flow.context, anchor, done.clone())

		parent := frames.pop() or FlowFrame()
		kind = parent.kind
		level = parent.level
		anchors = parent.anchors
		items = parent.items
		entries = parent.entries
		explicit = parent.explicit
		name = parent.name
		quoted_key = parent.quoted_key
		single = parent.single
		empty_key = false
		phase = 1

// A plain scalar cannot start with one of `]`, `}`, `,`, `%`, `@` or a backtick, nor
// with
// `-` or `?` followed by a space, tab or the end.
fn plain_may_start(text String) Bool:
	first := text.scalar_at(0, default: 0)
	if first == 0: return true
	if (
		first == 93
		or first == 125
		or first == 44
		or first == 37
		or first == 64
		or first == 96
	): return false

	if first == 45 or first == 63:
		second := text.scalar_at(1, default: 0)
		return not (second == 0 or second == 32 or second == 9)

	return true

// A mapping key may be a lone `-` or `?`: the colon that follows makes it a key, so no
// space follows the indicator (`-: 1`).
fn plain_key_may_start(text String) Bool:
	return text == "-" or text == "?" or plain_may_start(text)

fn quoted_or_nested(text String) Bool:
	return (
		text.contains("\"")
		or text.contains("'")
		or text.contains("[")
		or text.contains("{")
	)

// Whether the colon at offset `at` is part of an anchor or alias name (the word it ends
// starts with `&` or `*`; such a name runs to a blank), so it is not a mapping colon.
fn names_node(text String, at Int) Bool:
	// Quoted or bracketed text is scanned structurally, where a blank can sit inside
	// it.
	if quoted_or_nested(text): return false

	var start = at

	while start > 0:
		before := text.scalar_at(start - 1, default: 32)
		if before == 32 or before == 9: break

		start -= 1

	first := text.scalar_at(start, default: 0)
	return first == 38 or first == 42

// The offset of the first marker in text with no quotes or brackets, or -1. With
// `colon`, the marker is a `:` followed by a blank or the end; otherwise it is a `#`
// at the start of the text or after a blank.
fn plain_boundary(text String, colon Bool) Int:
	marker := if colon: ":" else: "#"
	var offset = 0

	while true:
		rest := text.view(offset, text.length())
		found := rest.index_of(marker) or (-1)
		if found < 0: return -1

		at := offset + found

		// A marker is one ASCII byte; a byte before it inside a longer scalar is no
		// blank.
		before := text.scalar_at(at - 1, -1)
		after := text.scalar_at(at + 1, -1)
		if (
			colon
			and (after == -1 or after == 32 or after == 9 or after == 10)
			and not names_node(text, at)
		): return at
		if not colon and (at == 0 or before == 32 or before == 9 or before == 10): return at

		offset = at + 1

// The result of a structure scan. `marker` is the offset of the requested marker, or -1
// when the scan reached the end first. `closed` is meaningful only in that case: it is
// true when no quote or flow collection is left open.
type StructureScan:
	marker Int
	closed Bool

// State shared by consecutive physical lines of a flow value.
type StructureState:
	quote Int = 0
	depth Int = 0
	node_start Bool = true
	json_node Bool = false
	tag Bool = false

fn scan_structure(text String, target String) StructureScan:
	var state = StructureState()
	return scan_structure_part(text, target, state)

// Scans quoted and flow nodes, treating quotes and brackets inside plain text as
// ordinary characters. `state` carries over between consecutive lines of one value.
fn scan_structure_part(
	text String,
	target String,
	var state StructureState,
) StructureScan:
	chars := text.scalar_values()
	var quote = state.quote
	var depth = state.depth
	var node_start = state.node_start
	var json_node = state.json_node
	var tag = state.tag
	var index = 0

	while index < chars.length():
		if tag:
			while index < chars.length() and chars[index] != 62: index += 1
			if index == chars.length(): break

			tag = false
			index += 1
			continue

		c := chars[index]
		next := chars.get_or(index + 1, 0)

		if quote != 0:
			if c == 92 and quote == 34: index += 1
			else if c == quote:
				if quote == 39 and next == 39: index += 1
				else:
					quote = 0
					json_node = true

			index += 1
			continue

		before := chars.get_or(index - 1, 0)

		if (c == 35 and (index == 0 or before == 32 or before == 9 or before == 10)):
			if target == "#":
				state = StructureState(quote, depth, node_start, json_node, tag)
				return StructureScan(index, closed: false)

			while index < chars.length() and chars[index] != 10: index += 1
			node_start = true
			json_node = false
			continue

		if node_start and (c == 38 or c == 33):
			index += 1

			if c == 33 and next == 60:
				while index < chars.length() and chars[index] != 62: index += 1

				if index < chars.length(): index += 1
				else: tag = true
			else:
				while (index < chars.length() and not structure_delimiter(chars[index])):
					index += 1

			json_node = false
			continue

		if node_start and (c == 34 or c == 39):
			quote = c
			node_start = false
			json_node = false
		else if node_start and (c == 91 or c == 123):
			depth += 1
			json_node = false
		else if depth > 0 and (c == 93 or c == 125):
			depth -= 1
			node_start = false
			json_node = true
		else if depth > 0 and c == 44:
			node_start = true
			json_node = false
		else if c == 58:
			separates := (json_node or separates_colon(next, depth > 0))

			if separates:
				if target == ":" and depth == 0:
					state = StructureState(quote, depth, node_start, json_node, tag)
					return StructureScan(index, closed: false)

				node_start = true
			else: node_start = false

			json_node = false
		else if (
			node_start
			and (c == 45 or c == 63)
			and (next == 0 or next == 32 or next == 9 or next == 10)
		):
			json_node = false
		else if c != 32 and c != 9 and c != 10:
			node_start = false
			json_node = false

		index += 1

	state = StructureState(quote, depth, node_start, json_node, tag)
	return StructureScan(-1, closed: quote == 0 and depth == 0)

fn structure_delimiter(code Int) Bool:
	return (
		code == 32
		or code == 9
		or code == 10
		or code == 44
		or code == 91
		or code == 93
		or code == 123
		or code == 125
	)

// The offset of the first mapping colon (with `colon`) or comment `#` outside quoted
// and flow values, or -1.
fn boundary(text String, colon Bool) Int:
	// Without the marker nothing can match; without quotes or brackets the first
	// candidate decides.
	if colon and not text.contains(":"): return -1
	if not colon and not text.contains("#"): return -1
	if not quoted_or_nested(text): return plain_boundary(text, colon)

	// The first candidate also decides when no quote or bracket precedes it.
	first := plain_boundary(text, colon)
	if first < 0: return -1
	if not quoted_or_nested(text.slice(0, first)): return first

	marker := scan_structure(text, if colon: ":" else: "#").marker
	if marker < 0: return marker

	return byte_at_scalar(text, marker)

fn uncomment(text String) String:
	index := boundary(text, colon: false)

	if index < 0:
		if not (text.ends_with(" ") or text.ends_with("\t")): return text.clone()
		if not complete(text): return text.clone()

		return blank_trim_end(text).clone()

	return blank_trim_end(text.slice(0, index)).clone()

fn indent(text String) Int:
	var result = 0
	while text.scalar_at(result, default: 0) == 32: result += 1
	return result

fn indentation(context Context, text String) Int!:
	spaces := indent(text)

	// Indentation is spaces only. A tab after it is separation, allowed before a scalar
	// or a flow collection but not before a block sequence entry, key or explicit key.
	if text.scalar_at(spaces, -1) == 9:
		rest := blank_trim_start(text)
		if (
			rest != ""
			and (
				sequence(rest)
				or rest.starts_with("?")
				or boundary(rest, colon: true) >= 0
			)
		): return error(invalid(context, "tabs cannot indent YAML"))

	return ok(spaces)

// Fills the per-line facts for `context.lines` from the bytes of the document they were
// split from.
fn classify(var context Context, data Bytes) Void:
	context.simple = []
	context.blank = []
	context.dash = []
	context.ind = []
	context.col = []

	total := data.length()
	var pos = 0

	while context.simple.length() < context.lines.length():
		end := data.index_of_byte(10, pos) or total
		var at = pos
		while at < end and data.get(at) == 32: at += 1

		indent_width := at - pos
		var simple = at < end
		var dash = false
		var colon = -1

		// An anchor or alias name runs to a blank, so a colon inside one is no key
		// colon.
		var named = false
		var token = true

		if simple:
			lead := data.get(at)
			dash = lead == 45 and (at + 1 == end or data.get(at + 1) == 32)
			if lead == 63: simple = false

		while simple and at < end:
			b := data.get(at)

			if (
				b < 32
				or b >= 127
				or b == 35
				or b == 34
				or b == 39
				or b == 91
				or b == 93
				or b == 123
				or b == 125
			): simple = false
			else if (
				b == 58
				and colon < 0
				and not named
				and (at + 1 == end or data.get(at + 1) == 32)
			): colon = (at - pos)

			if b == 32: token = true
			else:
				if token: named = b == 38 or b == 42
				token = false

			if b == 32: named = false
			at += 1

		if simple and data.get(end - 1) == 32: simple = false
		context.simple.append(simple)
		context.blank.append(indent_width == end - pos)
		context.dash.append(simple and dash)
		context.ind.append(indent_width)
		context.col.append(colon)
		pos = end + 1

fn skip(var context Context) Void:
	while context.index < context.lines.length():
		if context.blank[context.index]:
			context.index += 1
			continue

		if context.simple[context.index]: break

		line := blank_trim_start(context.lines[context.index])
		if line != "" and not line.starts_with("#"): break

		context.index += 1

// A document start or end marker at column zero cannot be node content.
fn document_marker(text String) Bool:
	first := text.scalar_at(0, default: 0)
	if first != 45 and first != 46: return false

	return (
		text == "---"
		or text.starts_with("--- ")
		or text.starts_with("---\t")
		or text == "..."
		or text.starts_with("... ")
		or text.starts_with("...\t")
	)

// A document-start marker followed by a space or tab, so content may follow on its
// line.
fn inline_start(text String) Bool:
	return text.starts_with("--- ") or text.starts_with("---\t")

fn sequence(text String) Bool:
	if text.scalar_at(0, default: 0) != 45: return false
	return (text == "-" or text.starts_with("- ") or text.starts_with("-\t"))

// Whether `text` opens an explicit mapping key: `?` alone or followed by a blank.
fn explicit_key(text String) Bool:
	if text.scalar_at(0, default: 0) != 63: return false
	return (text == "?" or text.starts_with("? ") or text.starts_with("?\t"))

// Whether `text` leaves no quote or flow collection open. An open one continues on the
// next physical line.
fn complete(text String) Bool:
	if not quoted_or_nested(text): return true
	return scan_structure(text, "").closed

// Whether a value starting with this scalar is a flow collection, quote, anchor, alias
// or tag (or, with `blank`, whitespace) rather than a plain scalar.
fn structured_lead(code Int, blank Bool = false) Bool:
	if blank and (code == 32 or code == 9 or code == 10): return true
	return (
		code == 91
		or code == 39
		or code == 34
		or code == 123
		or code == 42
		or code == 38
		or code == 33
	)

fn inline_value(
	var context Context,
	text String,
	depth Int,
	line Int,
	column Int,
	as_string Bool = false,
	parent Int = -1,
) Result[YamlValue, Error]:
	// A plain scalar needs no character scan: only its trimmed text and a count.
	if (
		text != ""
		and not structured_lead(text.scalar_at(0, default: 0), blank: true)
		and (
			not text.contains(":")
			or not (
				text.contains(": ")
				or text.contains(":\t")
				or text.contains(":\n")
				or text.ends_with(":")
			)
		)
		and plain_may_start(blank_trim(text))
	):
		count(context, depth)?
		if as_string: return ok(YamlValue.StringValue(blank_trim(text).clone()))

		return ok(plain(blank_trim(text).clone()))

	var joined = text.clone()
	structured := (
		text.starts_with("[")
		or text.starts_with("{")
		or text.starts_with("\"")
		or text.starts_with("'")
		or text.starts_with("&")
	)
	var stops List[Int] = []
	if (structured and boundary(context.lines[context.index - 1], colon: false) >= 0): stops.append(
		joined.scalar_length()
	)

	var state = StructureState()
	if structured:
		_scan := scan_structure_part(joined, "", state)

	var joined_length = joined.scalar_length()

	while (
		structured
		and (state.quote != 0 or state.depth != 0)
		and context.index < context.lines.length()
	):
		if document_marker(context.lines[context.index]): return error(
			invalid(context, "unexpected document marker in flow node")
		)

		// A continuation line of a node inside a collection is indented past that
		// collection; the common `key: [` layout may still close the bracket at the
		// parent's column.
		if (
			parent >= 0
			and blank_trim(context.lines[context.index]) != ""
			and not (
				state.quote == 0
				and blank_trim_start(
					context.lines[context.index]
				).starts_with("#")
			)
		):
			row := context.lines[context.index]
			lead := blank_trim_start(row).scalar_at(0, default: 0)
			closes := state.quote == 0 and (lead == 93 or lead == 125)
			if indent(row) <= parent and not closes: return error(
				invalid(
					context,
					"a continuation line must be indented past its parent",
				)
			)

		next := "\n".concat(context.lines[context.index])
		scan := scan_structure_part(next, "#", state)

		if scan.marker < 0:
			joined = joined.concat(next)
			joined_length += next.scalar_length()
		else:
			stops.append(joined_length + scan.marker)
			joined = joined.concat(next.slice(0, byte_at_scalar(next, scan.marker)))
			joined_length += scan.marker

		context.index += 1

	var flow = Flow(
		chars: joined.split("").clone(),
		codes: joined.scalar_values(),
		pos: 0,
		line: line,
		column: column,
		context: flow_context(context),
		delimited: false,
		stops: stops,
		force_string: as_string and not (
			text.starts_with("[")
			or text.starts_with("{")
		),
	)
	result := flow_value(flow, depth, key: false)?
	flow_space(flow)
	if cur(flow) != 0: return error(flow_invalid(flow, "unexpected trailing text"))

	context.values = flow.context.values
	context.anchors = flow.context.anchors.clone()
	context.sizes = flow.context.sizes.clone()
	return ok(result)

fn block_string(
	var context Context,
	header String,
	base Int,
	header_line Int,
	header_column Int,
) Result[YamlValue, Error]:
	var mode = ""
	var explicit = 0
	var offset = 0

	for c in header.slice(1, header.length()).split(""):
		offset += 1

		if (c == "+" or c == "-") and mode == "": mode = c
		else if "123456789".contains(c) and explicit == 0: explicit = (
			c.parse_int()
			or panic("called Optional.get() on null")
		)
		else: return error(
			yaml_invalid(
				line: header_line,
				column: header_column + offset,
				reason: "invalid block scalar header",
			)
		)

	// A root block scalar may start at column zero; an indentation indicator still
	// counts from column zero.
	var content_indent = explicit
	if explicit > 0 and base >= 0: content_indent = base + explicit
	if explicit == 0: content_indent = base + explicit

	scan_start := context.index
	var probe = scan_start

	if explicit == 0:
		var blank_indent = base + 1
		var blank_line = scan_start

		while (
			probe < context.lines.length()
			and context.lines[probe].slice(
				indent(context.lines[probe]),
				context.lines[probe].length(),
			) == ""
		):
			spaces := indent(context.lines[probe])

			if spaces > blank_indent:
				blank_indent = spaces
				blank_line = probe

			probe += 1

		if probe < context.lines.length(): content_indent = indent(
			(context.lines[probe])
		)

		if content_indent <= base: content_indent = blank_indent
		else if blank_indent > content_indent:
			return error(
				yaml_invalid(
					line: source_line(context, blank_line),
					column: content_indent + 1,
					reason: "leading empty line exceeds block scalar indentation",
				)
			)

	var parts List[String] = []

	while context.index < context.lines.length():
		line := context.lines[context.index]
		spaces := indent(line)

		if (line.slice(spaces, line.length()) != "" and spaces < content_indent):
			// A tab where the scalar's first line must be indented is no indentation.
			if parts.is_empty() and blank_trim(line) == "": return error(
				invalid(context, "tabs cannot indent YAML")
			)

			break

		if spaces == 0 and document_marker(line): break

		parts.append(line.slice(content_indent, line.length()).clone())
		context.index += 1

	var builder = ""
	var index = 0
	var content = false

	while index < parts.length():
		part := parts[index]
		if part != "": content = true
		builder += part

		var separator = "\n"

		if (
			header.starts_with(">")
			and part != ""
			and not part.starts_with(" ")
			and not part.starts_with("\t")
			and index + 1 < parts.length()
		):
			var next_index = index + 1
			while next_index < parts.length() and parts[next_index] == "":
				next_index += 1

			if next_index < parts.length():
				next := parts[next_index]

				if not next.starts_with(" ") and not next.starts_with("\t"):
					if next_index == index + 1: separator = " "
					else: separator = ""

		if (
			index + 1 == parts.length()
			and context.index == context.lines.length()
			and not context.final_break
			and blank_trim(part) != ""
		): separator = ""
		builder += separator
		index += 1

	var result = builder

	if mode != "+":
		final_break := result.ends_with("\n")

		// Count the final run of line feeds once: trimming one scalar at a time is
		// quadratic.
		pieces := result.split("\n")
		var trailing = 0
		while (trailing < pieces.length() and pieces.get_or(-1 - trailing, "x") == ""): trailing += 1
		if trailing == pieces.length(): trailing -= 1
		result = result.slice(0, (result.length() - trailing))
		if (mode != "-" and content and final_break): result = result.concat("\n")

	return ok(YamlValue.StringValue(result))

// Whether a plain scalar may continue on a following line: false when the next
// non-blank line is already known to sit at or left of `base`.
fn may_continue(context Context, base Int) Bool:
	first := context.index
	var probe = first

	while probe < context.lines.length():
		if context.blank[probe]:
			probe += 1
			continue

		return not (context.simple[probe] and context.ind[probe] <= base)

	return false

// A plain scalar's text with the more-indented lines that continue it, joined by the
// folding rules. The caller has checked that a continuation is possible.
fn plain_continuation(var context Context, remainder String, base Int) String!:
	var joined = ""
	joined += remainder

	scan_start := context.index
	var probe = scan_start
	var blanks = 0

	while probe < context.lines.length():
		line := context.lines[probe]

		if blank_trim(line) == "":
			blanks += 1
			probe += 1
			continue

		next := uncomment(line.clone())
		if (blank_trim(next) == "" or indent(next) <= base or document_marker(next)): break

		context.index = probe

		_indent := indentation(context, next)?
		if boundary(next, colon: true) >= 0: return error(
			invalid(context, "unexpected indented collection")
		)

		var separator = " "

		if blanks > 0:
			separator = ""

			while blanks > 0:
				separator = separator.concat("\n")
				blanks -= 1

		joined += separator
		joined += blank_trim(next)
		probe += 1
		context.index = probe
		if (not context.simple[probe - 1] and boundary(line, colon: false) >= 0): break

	return ok(joined)

// Standalone plain scalars may continue at their header column, but block scalars
// measure content from their containing collection (column zero at the document root).
fn block_value(
	var context Context,
	text String,
	base Int,
	depth Int,
	indentless Bool,
	column Int,
	block_base Int? = null,
) YamlValue!:
	start_line := source_line(context, context.index - 1)
	var origin = source_column(context, context.index - 1, column)
	var remainder = blank_trim_start(text).clone()
	var anchor = ""
	var lead = remainder.scalar_at(0, default: 0)
	var as_string = false
	var tagged = false

	// Node properties, an anchor and a tag in either order, come before the content.
	while lead == 38 or lead == 33:
		var flow = Flow(
			chars: remainder.split("").clone(),
			codes: [],
			pos: 0,
			line: start_line,
			column: origin,
			context: flow_context(context),
			delimited: false,
		)

		if lead == 38:
			advance(flow)
			anchor = anchor_name(flow)?
		else:
			tag := tag_token(flow)?
			as_string = as_string or string_tag(tag)
			tagged = true

		previous_length := remainder.scalar_length()
		remainder = blank_trim_start(
			remainder.slice(
				byte_at_scalar(remainder, flow.pos),
				remainder.length(),
			)
		)
		origin += previous_length - remainder.scalar_length()
		lead = remainder.scalar_at(0, default: 0)
		if lead == 42: return error(
			yaml_invalid(
				line: start_line,
				column: origin,
				reason: "an alias cannot have node properties",
			)
		)

	var result = YamlValue.Null

	if lead == 124 or lead == 62:
		count(context, depth)?
		result = block_string(
			context,
			blank_trim_end(remainder),
			base: block_base or base,
			header_line: start_line,
			header_column: origin,
		)?
	else if remainder != "":
		if not structured_lead(lead):
			remainder = blank_trim_end(remainder).clone()

			// An inline comment ends a nonempty plain scalar, even when the next line
			// would otherwise have continuation indentation. Simple lines contain no
			// comments.
			if (
				(
					context.simple[context.index - 1]
					or boundary(
						context.lines[context.index - 1],
						colon: false,
					) < 0
				)
				and may_continue(context, base)
			):
				remainder = plain_continuation(context, remainder, base)?

		result = inline_value(
			context,
			remainder,
			depth,
			start_line,
			origin,
			as_string,
			parent: base,
		)?
	else:
		skip(context)

		if context.index < context.lines.length():
			line := uncomment(context.lines[context.index])
			next_indent := indentation(context, line)?

			// Properties on a line of their own bind the node after them, which only
			// has to be indented past the parent.
			parent := block_base or base

			if (
				next_indent > parent
				or (
					indentless
					and next_indent == parent
					and sequence(blank_trim_start(line))
				)
			):
				next_content := blank_trim_start(line)
				next_lead := next_content.scalar_at(0, default: 0)
				if (
					(
						(anchor != "" and next_lead == 38)
						or (tagged and next_lead == 33)
					)
					and boundary(next_content, colon: true) < 0
				): return error(
					invalid(
						context,
						"a node cannot have properties on two lines",
					)
				)

				result = block(
					context,
					next_indent,
					depth,
					scalar_base: block_base or base,
					mapping_value: indentless,
				)?
			else:
				count(context, depth)?
				if as_string: result = YamlValue.StringValue("")
		else:
			count(context, depth)?
			if as_string: result = YamlValue.StringValue("")

	if anchor != "": define_anchor(context, anchor, result.clone())
	return ok(result)

fn pad(width Int) String:
	return "".pad_start(width, " ")

// Columns of the nested sequence levels opened by consecutive compact `- ` indicators.
fn nested_columns(line String, base Int) List[Int]:
	chars := line.split("")
	var columns List[Int] = []
	var marker = base

	while chars.get_or(marker, "") == "-":
		var next = marker + 1
		while chars.get_or(next, "") == " ": next += 1
		if next == marker + 1 or chars.get_or(next, "") != "-": break

		after := chars.get_or(next + 1, "")
		if (after != "" and after != " " and after != "\t"): break

		columns.append(next)
		marker = next

	return columns

fn sequence_items(
	var context Context,
	var values List[YamlValue],
	base Int,
	depth Int,
) Void!:
	while context.index < context.lines.length():
		skip(context)
		if context.index >= context.lines.length(): break

		fast := context.simple[context.index]
		var line = ""
		var line_indent = 0
		var item = ""
		var compact = false

		if fast:
			line_indent = context.ind[context.index]
			if line_indent != base or not context.dash[context.index]: break

			line = context.lines[context.index].clone()
			item = blank_trim_start(line.slice(line_indent + 1, line.length()))
			compact = (
				context.col[context.index] >= 0
				or sequence(item)
				or explicit_key(item)
			)
		else:
			line = uncomment(context.lines[context.index])
			line_indent = indentation(context, line)?
			if line_indent < base: break
			if line_indent != base or not sequence(blank_trim_start(line)): break

			item = blank_trim_start(
				blank_trim_start(line).slice(
					1,
					(blank_trim_start(line).length()),
				)
			)
			compact = (
				sequence(item)
				or explicit_key(item)
				or boundary(item, colon: true) >= 0
			)

			// A tab cannot indent a nested sequence: `-<tab>- x` is invalid.
			after := blank_trim_start(line).slice(1, blank_trim_start(line).length())
			gap := after.slice(0, after.length() - item.length())
			if gap.contains("\t") and sequence(item): return error(
				invalid(
					context,
					"a tab cannot indent a nested sequence",
				)
			)

		var chain List[Int] = []
		if item.starts_with("-"): chain = nested_columns(line, base)

		if not chain.is_empty():
			// A run of compact sequence indicators (`- - x`) opens one level per
			// indicator. Scan the line once and rewrite it once instead of per level.
			innermost := chain[chain.length() - 1]
			var frames List[List[YamlValue]] = []
			var level = 1

			while level <= chain.length():
				count(context, (depth + level))?
				frames.append([])
				level += 1

			// Keep comments in the virtual source line so plain continuation can see
			// them.
			raw := context.lines[context.index].clone()
			context.simple.set(context.index, false)
			context.lines.set(
				context.index,
				pad(innermost).concat(
					(raw.slice(innermost, raw.length()))
				),
			)
			level = chain.length()

			var nested = frames[level - 1].clone()
			sequence_items(
				context: context,
				values: nested,
				base: innermost,
				depth: (depth + level),
			)?

			var value = YamlValue.ArrayValue(nested)
			level -= 1

			while level >= 1:
				nested = frames[level - 1].clone()
				nested.append(value)
				sequence_items(
					context: context,
					values: nested,
					base: chain[level - 1],
					depth: (depth + level),
				)?
				value = YamlValue.ArrayValue(nested)
				level -= 1

			values.append(value)
		else if compact:
			// Treat a compact mapping/sequence as a virtual indented first line.
			// Its column follows the indicator, so extra spaces move the nested base.
			marker := blank_trim_start(line).slice(1, (blank_trim_start(line).length()))
			var gap = indent(marker)
			if gap == 0: gap = 1

			column := base + 1 + gap
			shift := column - (line.scalar_length() - item.scalar_length())

			if shift != 0:
				if context.shift_row != context.index:
					context.shift_row = context.index
					context.shift_column = 0

				context.shift_column -= shift

			if fast:
				if context.col[context.index] >= 0: context.col.set(
					context.index,
					context.col[context.index] + shift,
				)
				context.ind.set(context.index, column)
				context.dash.set(context.index, sequence(item))
				if item.scalar_at(0, default: 0) == 63: context.simple.set(
					context.index,
					false,
				)

			var rewritten = pad(column).concat(item)

			if not fast:
				raw := context.lines[context.index]
				rewritten = rewritten.concat(raw.slice(line.length(), raw.length()))

			context.lines.set(context.index, rewritten)
			values.append(block(context, column, (depth + 1), scalar_base: base)?)
		else:
			context.index += 1
			values.append(
				block_value(
					context: context,
					text: item,
					base: base,
					depth: (depth + 1),
					indentless: false,
					column: line.scalar_length() - item.scalar_length() + 1,
				)?
			)

	return ok()

// Whether `text` starts with the indicator `code` followed by a blank or the end.
fn indicator(text String, code Int) Bool:
	if text.scalar_at(0, default: 0) != code: return false

	second := text.scalar_at(1, default: 0)
	return second == 0 or second == 32 or second == 9

type ExplicitEntry:
	name String
	value YamlValue

// One `? key` and `: value` pair of a block mapping, either part optional. The key must
// be a scalar; a missing value is null and a missing key is the empty string.
fn explicit_entry(var context Context, base Int, depth Int) ExplicitEntry!:
	var name = ""
	var value = YamlValue.Null
	start := context.lines[context.index].clone()
	lead := blank_trim_start(start).clone()

	if lead.scalar_at(0, default: 0) == 63:
		var rest = blank_trim_start(lead.slice(1, lead.length()))
		column := start.scalar_length() - rest.scalar_length() + 1
		rest = uncomment(rest)
		if sequence(rest) or (rest != "" and boundary(rest, colon: true) >= 0): return error(
			yaml_unsupported(
				line: source_line(context, context.index),
				reason: "mapping keys must be scalars, not a collection",
			)
		)

		context.index += 1

		node := block_value(
			context: context,
			text: rest,
			base: base,
			depth: (depth + 1),
			indentless: false,
			column: column,
		)?
		scalar := key_text(node)
		if scalar == null: return error(
			yaml_unsupported(
				line: source_line(context, context.index - 1),
				reason: "mapping keys must be scalars, not a collection",
			)
		)

		if rest != "" or node != YamlValue.Null: name = scalar
		skip(context)

	if context.index >= context.lines.length(): return ok(
		ExplicitEntry(name: name, value: value)
	)

	row := context.lines[context.index].clone()
	value_lead := blank_trim_start(row).clone()
	if indent(row) != base or not indicator(value_lead, 58): return ok(
		ExplicitEntry(name: name, value: value)
	)

	var text = blank_trim_start(value_lead.slice(1, value_lead.length()))
	column := row.scalar_length() - text.scalar_length() + 1
	text = uncomment(text)

	// A collection may start on the indicator's line, as in `: - one`.
	if sequence(text) or (text != "" and boundary(text, colon: true) >= 0):
		context.simple.set(context.index, false)

		content := column - 1
		context.lines.set(context.index, pad(content).concat(text))
		value = block(context, content, depth + 1, scalar_base: base)?
	else:
		context.index += 1
		value = block_value(
			context: context,
			text: text,
			base: base,
			depth: (depth + 1),
			indentless: true,
			column: column,
		)?

	return ok(ExplicitEntry(name: name, value: value))

fn block(
	var context Context,
	base Int,
	depth Int,
	scalar_base Int,
	mapping_value Bool = false,
) YamlValue!:
	skip(context)

	var first = ""
	var is_sequence = false
	var has_colon = false

	if context.simple[context.index]:
		is_sequence = context.dash[context.index]
		has_colon = not is_sequence and context.col[context.index] >= 0
	else:
		first = blank_trim_start(uncomment(context.lines[context.index]))
		is_sequence = sequence(first)
		has_colon = (
			not is_sequence
			and (boundary(first, colon: true) >= 0 or indicator(first, 63))
		)

	if (
		context.split_line >= 0
		and context.index == context.split_line + 1
		and (is_sequence or has_colon)
	): return error(
		invalid(
			context,
			"block collection must start after the document marker line",
		)
	)

	if is_sequence:
		count(context, depth)?

		var values List[YamlValue] = []
		sequence_items(context: context, values: values, base: base, depth: depth)?
		return ok(YamlValue.ArrayValue(values))

	if has_colon:
		count(context, depth)?

		var values = Map[String, YamlValue]()
		var explicit = Set[String]()

		while context.index < context.lines.length():
			skip(context)
			if context.index >= context.lines.length(): break

			marker_row := context.lines[context.index].clone()
			marker := blank_trim_start(marker_row).clone()

			if (
				indent(marker_row) == base
				and (indicator(marker, 63) or indicator(marker, 58))
			):
				entry := explicit_entry(context, base, depth)?
				if explicit.contains(entry.name): return error(
					invalid(context, "duplicate mapping key")
				)

				explicit.add(entry.name.clone())
				values.add(entry.name.clone(), entry.value.clone())
				continue

			var line_indent = 0
			var name = ""
			var text = ""
			var value_column = 1

			if context.simple[context.index]:
				line_indent = context.ind[context.index]
				if line_indent != base or context.dash[context.index]: break

				colon := context.col[context.index]
				if colon < 0: break

				raw := context.lines[context.index]
				name = blank_trim(raw.slice(line_indent, colon))
				text = blank_trim_start(raw.slice(colon + 1, raw.length()))
				value_column = raw.scalar_length() - text.scalar_length() + 1
			else:
				line := uncomment(context.lines[context.index])
				line_indent = indentation(context, line)?
				if line_indent != base or sequence(blank_trim_start(line)): break

				content := blank_trim_start(line)
				colon := boundary(content, colon: true)
				if colon < 0: break

				name = blank_trim(content.slice(0, colon))
				text = blank_trim_start(content.slice(colon + 1, content.length()))
				value_column = line.scalar_length() - text.scalar_length() + 1

			var key_start = name.scalar_at(0, default: 0)
			var key_anchor = ""
			var had_properties = false

			// Node properties before a key: a tag is dropped, an anchor names the key.
			while key_start == 33 or key_start == 38:
				var word_end = 0

				while word_end < name.scalar_length():
					ch := name.scalar_at(word_end, default: 0)
					if ch == 32 or ch == 9: break

					word_end += 1

				cut := byte_at_scalar(name, word_end)
				word := name.slice(0, cut)
				if key_start == 38: key_anchor = word.slice(1, word.length())
				name = blank_trim_start(name.slice(cut, name.length())).clone()
				key_start = name.scalar_at(0, default: 0)
				had_properties = true

			quoted_key := key_start == 34 or key_start == 39
			var plain_key = name != ""

			if quoted_key:
				var flow = Flow(
					chars: name.split("").clone(),
					codes: [],
					pos: 0,
					line: source_line(context, context.index),
					column: source_column(
						context,
						context.index,
						line_indent + 1,
					),
					context: flow_context(context),
					delimited: false,
				)
				name = quoted(flow)?
				if flow.pos != flow.chars.length(): return error(
					invalid(context, "invalid quoted key")
				)
			else if key_start == 91 or key_start == 123:
				return error(
					yaml_unsupported(
						line: source_line(
							context,
							context.index,
						),
						reason: "mapping keys must be scalars, not a collection",
					)
				)
			else if key_start == 42:
				// An alias key stands for the scalar it names.
				if had_properties: return error(
					invalid(
						context,
						"an alias cannot have node properties",
					)
				)

				alias_name := name.slice(1, name.length())
				aliased := context.anchors.get(alias_name)
				if aliased == null: return error(invalid(context, "unknown anchor"))

				alias_text := key_text(aliased)
				if alias_text == null: return error(
					yaml_unsupported(
						line: source_line(
							context,
							context.index,
						),
						reason: "mapping keys must be scalars, not a collection",
					)
				)

				name = alias_text
				plain_key = false

			if (
				not quoted_key
				and plain_key
				and (
					not plain_key_may_start(name)
					or key_start == 124
					or key_start == 62
				)
			): return error(
				invalid(
					context,
					"a plain mapping key cannot start with an indicator character",
				)
			)
			if explicit.contains(name): return error(
				invalid(context, "duplicate mapping key")
			)

			explicit.add(name.clone())
			if key_anchor != "": define_anchor(
				context,
				key_anchor,
				YamlValue.StringValue(name.clone()),
			)

			key_line := source_line(context, context.index)
			key_column := source_column(context, context.index, line_indent + 1)
			context.index += 1

			value := block_value(
				context: context,
				text: text,
				base: base,
				depth: (depth + 1),
				indentless: true,
				column: value_column,
			)?

			if name == "<<" and not quoted_key:
				merge(line: key_line, column: key_column, target: values, value: value)?
			else:
				values.add(name, value)

		return ok(YamlValue.ObjectValue(values))

	if first == "": first = blank_trim_start(context.lines[context.index])
	context.index += 1
	return block_value(
		context: context,
		text: first,
		// A scalar or anchor on its own line may continue at the same indentation.
		base: base - 1,
		depth: depth,
		indentless: mapping_value,
		column: base + 1,
		block_base: scalar_base
	)

// Reads the directive lines before a document. `%YAML` accepts any 1.x version (the
// spec asks a 1.2 parser to read it with a warning), `%TAG` declares a tag handle
// prefix, and an unknown directive is ignored.
fn directives(var context Context) Void!:
	var seen_version = false

	while (
		context.index < context.lines.length()
		and context.lines[context.index].starts_with("%")
	):
		var words List[String] = []
		for word in uncomment(context.lines[context.index]).replace(
			"\t",
			" ",
		).split(" "):
			if word != "": words.append(word.clone())

		line := source_line(context, context.index)

		if words[0] == "%YAML":
			if seen_version: return error(invalid(context, "duplicate %YAML directive"))

			seen_version = true

			var parts List[String] = []
			if words.length() == 2: parts = words[1].split(".").clone()
			if (
				parts.length() != 2
				or (parts[0].parse_int() == null)
				or (parts[1].parse_int() == null)
			): return error(invalid(context, "invalid %YAML directive"))
			if parts[0] != "1": return error(
				yaml_unsupported(
					line: line,
					reason: "only YAML 1.x documents are supported",
				)
			)
		else if words[0] == "%TAG":
			if words.length() != 3: return error(
				invalid(context, "invalid %TAG directive")
			)

			handle := words[1]
			if not (
				handle == "!"
				or handle == "!!"
				or (
					handle.length() > 2
					and handle.starts_with("!")
					and handle.ends_with("!")
				)
			): return error(invalid(context, "invalid %TAG handle"))
			if context.tag_handles.contains(handle): return error(
				invalid(context, "duplicate %TAG directive")
			)

			context.tag_handles.add(handle.clone(), words[2].clone())

		context.index += 1
		skip(context)

// A flow value needs only the limits, counters and anchors, so it gets a context
// without the document lines and per-line facts (copying them for every value made
// parsing quadratic).
fn flow_context(context Context) Context:
	return Context(
		lines: [],
		final_break: context.final_break,
		index: context.index,
		max_depth: context.max_depth,
		max_values: context.max_values,
		values: context.values,
		anchors: context.anchors.clone(),
		sizes: context.sizes.clone(),
		simple: [],
		blank: [],
		dash: [],
		ind: [],
		col: [],
		tag_handles: context.tag_handles.clone(),
	)

fn validate(var context Context, value YamlValue, depth Int) Void!:
	count(context, depth)?

	match value:
		ArrayValue(values):
			for item in values: validate(context, item, (depth + 1))?
		ObjectValue(values):
			for entry in values: validate(context, entry.value, (depth + 1))?
		_: void

fn open_stream(text String, options YamlOptions) Context!:
	for limit in [options.max_bytes, options.max_depth, options.max_values]:
		value := limit
		if value != null:
			if value < 0: return error(Error("invalid YAML input", kind: "EINVAL"))

	if not within(text.length(), options.max_bytes): return error(
		Error("YAML limit exceeded", kind: "EOVERFLOW")
	)

	var normalized = text.replace("\r\n", "\n").replace("\r", "\n")
	if normalized.starts_with("\u{feff}"): normalized = normalized.slice(
		3,
		normalized.length(),
	)

	for code in normalized.scalar_values():
		if (
			(code < 32 and code != 9 and code != 10)
			or (code >= 127 and code <= 159 and code != 133)
		):
			// The first occurrence of this invalid scalar is necessarily the first
			// one encountered above; find its position only on the rejection path.
			character := from_scalars([code]).get_or("")
			at := normalized.view(
				0,
				normalized.index_of(character) or 0,
			).scalar_length()
			position := cursor_position(normalized.split(""), at, 1, 1)
			return error(
				yaml_invalid(
					line: position.line,
					column: position.column,
					reason: "invalid control character",
				)
			)

	var context = Context(
		lines: normalized.split("\n").clone(),
		final_break: normalized.ends_with("\n"),
		index: 0,
		max_depth: options.max_depth,
		max_values: options.max_values,
		values: 0,
		anchors: Map[String, YamlValue](),
		sizes: Map[String, Int](),
		simple: [],
		blank: [],
		dash: [],
		ind: [],
		col: [],
	)

	// split's synthetic terminal empty line is not scalar content.
	if normalized.ends_with("\n"): context.lines.remove(context.lines.length() - 1)
	classify(context, normalized.to_bytes())
	skip(context)
	return ok(context)

// Reads one document, from its directives and `---` marker to its body and optional
// `...` marker. Anchors, tag handles and the value budget belong to a single document.
fn document(var context Context, options YamlOptions) YamlValue!:
	context.anchors = Map[String, YamlValue]()
	context.sizes = Map[String, Int]()
	context.tag_handles = Map[String, String]()
	context.values = 0
	context.explicit_end = false
	context.absent_document = false

	var marked = false

	if (
		context.index < context.lines.length()
		and context.lines[context.index].starts_with("%")
	):
		directives(context)?
		if (
			context.index >= context.lines.length()
			or (
				uncomment(context.lines[context.index]) != "---"
				and not inline_start(context.lines[context.index])
			)
		): return error(invalid(context, "directive requires document start"))

	// Content after the marker on the same line starts the document body.
	if (
		context.index < context.lines.length()
		and inline_start(context.lines[context.index])
	):
		line := context.lines[context.index]
		rest := line.slice(4, line.length())

		if not blank_trim(rest).starts_with("#"):
			context.split_line = context.index
			context.lines.splice(context.index, 1, ["---", rest])
			classify(context, context.lines.join("\n").to_bytes())

	if (
		context.index < context.lines.length()
		and uncomment((context.lines[context.index])) == "---"
	):
		context.index += 1
		marked = true
		skip(context)

	var result = YamlValue.Null
	var has_body = false

	if (
		context.index < context.lines.length()
		and uncomment((context.lines[context.index])) != "..."
		and not document_marker(context.lines[context.index])
	):
		has_body = true
		result = block(
			context,
			indentation(context, (context.lines[context.index]))?,
			1,
			scalar_base: -1,
		)?

	skip(context)
	context.absent_document = not marked and not has_body

	if (
		context.index < context.lines.length()
		and uncomment((context.lines[context.index])) == "..."
	):
		context.index += 1
		context.explicit_end = true
		skip(context)

	if (options.max_depth == null) and (options.max_values == null): return ok(result)

	// Without aliases, parsing already counted every container and leaf at its depth.
	if context.values > 0 and context.anchors.is_empty(): return ok(result)

	context.values = 0
	validate(context, result, 1)?
	return ok(result)

// Parses a single YAML document. A stream of several documents is an error; use
// `parse_all` for it. Invalid input returns `EBADMSG` and unsupported YAML syntax returns
// `ENOTSUP`; both errors include the source location.
export fn parse(text String, options YamlOptions = YamlOptions()) YamlValue!:
	var context = open_stream(text, options)?
	result := document(context, options)?
	if context.index != context.lines.length(): return error(
		invalid(context, "unexpected indentation or additional document")
	)

	return ok(result)

// Parses a stream of YAML documents separated by `---` or ended by `...`, returning one
// value per document in order. A document with no content is null; input with no
// document at all is an empty list. Anchors, tag handles and limits apply to each
// document on its own.
export fn parse_all(text String, options YamlOptions = YamlOptions()) List[YamlValue]!:
	var context = open_stream(text, options)?
	var documents List[YamlValue] = []

	while context.index < context.lines.length():
		value := document(context, options)?
		if not context.absent_document: documents.append(value)
		if context.index >= context.lines.length(): break

		line := uncomment(context.lines[context.index])
		starts := (
			context.explicit_end
			or line == "---"
			or inline_start(context.lines[context.index])
		)
		if not starts: return error(
			invalid(
				context,
				"unexpected indentation or additional document",
			)
		)

	return ok(documents)

fn format_key(key String) String:
	var plain = key != ""
	var first = true

	for code in key.scalar_values():
		word := (
			(code >= 97 and code <= 122)
			or (code >= 65 and code <= 90)
			or code == 95
		)
		digit := code >= 48 and code <= 57
		if not (word or digit or code == 45): plain = false
		if first and (digit or code == 45): plain = false
		first = false
		if not plain: break

	if plain and key.length() <= 5:
		if ["null", "true", "false", "yes", "no", "on", "off", "y", "n"].contains(
			key.lower()
		): plain = false
	if plain: return key.clone()

	return quote_text(key, escape_c1: true)

// A number keeps its original token, so it must resolve back to a number.
fn valid_number(text String) Bool:
	// Plain decimal integers resolve to themselves; anything else goes through the
	// parser.
	var integer = text != ""
	var at = 0

	for code in text.scalar_values():
		if not (code >= 48 and code <= 57 or (at == 0 and (code == 45 or code == 43))):
			integer = false
			break

		at += 1

	if integer and at > 1 or (integer and text.scalar_at(0) >= 48): return true
	if parsed := parse(text): return parsed == YamlValue.NumberValue(text.clone())

	return false

fn scalar_text(value YamlValue) String!:
	match value:
		Null: return ok("null")
		BoolValue(flag): return ok(flag.to_string())
		StringValue(text): return ok(quote_text(text, escape_c1: true))
		NumberValue(text):
			if not valid_number(text.clone()): return error(
				Error("invalid YAML input", kind: "EINVAL")
			)
			return ok(text.clone())
		ArrayValue(values):
			if values.is_empty(): return ok("[]")
			return ok("")
		ObjectValue(values):
			if values.is_empty(): return ok("{}")
			return ok("")

fn is_block(value YamlValue) Bool:
	match value:
		ArrayValue(values): return not values.is_empty()
		ObjectValue(values): return not values.is_empty()
		_: return false

fn emit_block(var out String, value YamlValue, indent String) Result[Void, Error]:
	match value:
		ArrayValue(values):
			for item in values:
				out += indent

				if is_block(item):
					out += "-\n"
					emit_block(out, item, indent.concat("  "))?
				else:
					text := scalar_text(item.clone())?
					out += "- "
					out += text
					out += "\n"

			return ok()
		ObjectValue(values):
			for entry in values.entries():
				out += indent
				out += format_key(entry.key.clone())

				if is_block(entry.value):
					out += ":\n"
					emit_block(out, entry.value, indent.concat("  "))?
				else:
					text := scalar_text(entry.value.clone())?
					out += ": "
					out += text
					out += "\n"

			return ok()
		_: return ok()

// Writes a YAML value in block style with double-quoted strings. Output longer than
// `max_bytes` returns `EOVERFLOW`, and a negative `max_bytes` returns `EINVAL`.
export fn stringify(value YamlValue, max_bytes Int? = null) String!:
	limit := max_bytes
	if limit != null:
		if limit < 0: return error(Error("invalid YAML input", kind: "EINVAL"))

	var out = ""

	if is_block(value.clone()): emit_block(out, value, "")?
	else:
		text := scalar_text(value.clone())?
		out += text.concat("\n")

	text := out
	if not within(text.length(), max_bytes): return error(
		Error("YAML limit exceeded", kind: "EOVERFLOW")
	)

	return ok(text)
