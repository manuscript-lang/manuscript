// Edits to a TOML document that keep its comments, blank lines and formatting. A
// `TomlDocument` holds the text and where each statement sits (`layout` in
// `@std/data/toml.ms`); `set_key` and `remove_key` change one key of one table by splicing the
// text, then read the result again, so an edit that would break the document is an
// error and never a bad file.
//
// A comment or blank line belongs to the statement that follows it: removing a
// statement removes the comments above it, and a table added to the end of the document
// goes after its last statement, before its trailing comments. A key added to a table
// goes where the table is written: after the last statement of its `[header]`, else
// after the last dotted key that defines it, else in a new `[header]` before its first
// sub-table, else in a new `[header]` at the end.
import (
	TomlStatement,
	TomlStatementKind,
	TomlValue,
	dotted,
	format_key,
	inline_value,
	layout
) from "@std/data/toml.ms"

// A document and its layout. `text` has `\n` line breaks and offsets in `statements`
// refer to it; `crlf` says the source used `\r\n`, which `to_string` restores.
export type TomlDocument:
	// The document with `\n` line breaks.
	text: String
	// Whether the source used `\r\n` line breaks, which `to_string` writes back.
	crlf: Bool
	// The parsed document, the same value `parse` returns for the text.
	value: TomlValue
	// Where each top-level statement sits in `text`, in document order.
	statements: List[TomlStatement]

fn invalid(message: String) Error:
	return Error(message, kind: "EINVAL")

fn assemble(text: String, crlf: Bool) TomlDocument!:
	read := layout(text)?
	return ok(
		TomlDocument(
			read.text.clone(),
			crlf,
			read.value.clone(),
			read.statements.clone(),
		)
	)

// Reads `text` as a document. Invalid TOML is an error like `parse`'s.
export fn parse_document(text: String) TomlDocument!:
	return assemble(text, text.contains("\r\n"))

// The document as text, with the line breaks it was read with.
export fn to_string(document: TomlDocument) String:
	if document.crlf: return document.text.replace("\n", "\r\n")
	return document.text.clone()

fn child_of(value: TomlValue, key: String) TomlValue?:
	match value:
		TableValue(entries): return entries.get(key)
		_: return none

// The value at `path`, or none; the empty path is the whole document.
export fn value_at(document: TomlDocument, path: List[String]) TomlValue?:
	var current = document.value.clone()

	for part in path:
		step := child_of(current, part)

		if found := step: current = found.clone()
		else: return none

	return current

fn joined(left: List[String], right: List[String]) List[String]:
	var out = left.clone()
	for part in right: out.append(part.clone())
	return out

fn starts_with(path: List[String], prefix: List[String]) Bool:
	if path.length() < prefix.length(): return false

	for i in 0..prefix.length():
		if path[i] != prefix[i]: return false
	return true

// The full path a statement names: a header's table, or a pair's table and keys.
fn path_of(statement: TomlStatement) List[String]:
	return joined(statement.table, statement.keys)

fn is_header(statement: TomlStatement) Bool:
	return statement.kind != TomlStatementKind.Pair

fn splice(text: String, start: Int, end: Int, replacement: String) String:
	return text.slice(0, start) + replacement + text.slice(end, text.length())

// `text` ending with a line break, when it has any text.
fn terminated(text: String) String:
	if text.is_empty() or text.ends_with("\n"): return text.clone()
	return text + "\n"

// The statement that holds `table` as an inline value (`table = { ... }`, or a value
// that contains it), or -1.
fn inline_holder(document: TomlDocument, table: List[String]) Int:
	for i in 0..document.statements.length():
		statement := document.statements[i]
		if (
			statement.kind == TomlStatementKind.Pair
			and starts_with(table, path_of(statement))
		): return i

	return -1

// Whether `table` is written as an inline value (`table = { ... }`), which `set`
// refuses.
export fn is_inline_table(document: TomlDocument, table: List[String]) Bool:
	return inline_holder(document, table) >= 0

// Where a key of `table` is written: the index of the last statement in the body of its
// header, or -1.
fn header_body_end(document: TomlDocument, table: List[String]) Int:
	var header = -1

	for i in 0..document.statements.length():
		statement := document.statements[i]
		if statement.kind == TomlStatementKind.Header and statement.table == table: header = i

	if header < 0: return -1

	var last = header
	var i = header + 1

	while i < document.statements.length() and not is_header(document.statements[i]):
		last = i
		i += 1

	return last

// The last statement that defines `table` by dotted keys (`table.key = value`), or -1;
// `parts` is how many of its key parts name the table.
fn dotted_home(document: TomlDocument, table: List[String]) Int:
	var home = -1

	for i in 0..document.statements.length():
		statement := document.statements[i]
		path := path_of(statement)
		if (
			statement.kind == TomlStatementKind.Pair
			and path.length() > table.length()
			and starts_with(path, table)
		):
			if statement.keys.length() > path.length() - table.length(): home = i

	return home

// The first sub-table header of `table`, or -1.
fn first_sub_table(document: TomlDocument, table: List[String]) Int:
	for i in 0..document.statements.length():
		statement := document.statements[i]
		if (
			is_header(statement)
			and statement.table.length() > table.length()
			and starts_with(statement.table, table)
		): return i

	return -1

// The text of `document` with the statements at `indexes` (ascending) and the comments
// and blank lines above them removed.
fn without_statements(document: TomlDocument, indexes: List[Int]) TomlDocument!:
	var text = document.text.clone()
	var at = indexes.length()

	while at > 0:
		at -= 1

		index := indexes[at]
		start := if index > 0: document.statements[index - 1].end else: 0
		text = splice(text, start, document.statements[index].end, "")

	return assemble(text, document.crlf)

// The indexes of the statements that write `path` or anything under it.
fn defining(document: TomlDocument, path: List[String]) List[Int]:
	var found = List[Int]()
	for i in 0..document.statements.length():
		if starts_with(path_of(document.statements[i]), path): found.append(i)
	return found

fn entry_text(keys: List[String], value: TomlValue) String:
	return dotted(keys) + " = " + inline_value(value)

// Inserts `text` after the statement at `index`.
fn insert_after(document: TomlDocument, index: Int, text: String) TomlDocument!:
	whole := terminated(document.text)
	end := if document.statements[index].end >= document.text.length(): whole.length() else: document.statements[
		index
	].end
	return assemble(splice(whole, end, end, text), document.crlf)

// `document` with `key` set to `value` in `table`: a value written as `key = ...` is
// replaced, comments after it dropped; a new key goes where the table is written. A
// table written inline, or a key written as sub-tables or several dotted keys, is
// replaced as a whole or refused (an inline table).
export fn set_key(
	document: TomlDocument,
	table: List[String],
	key: String,
	value: TomlValue,
) TomlDocument!:
	if inline_holder(document, table) >= 0: return error(
		invalid(
			f"{dotted(table)} is written as an inline table; edit it by hand"
		)
	)

	target := joined(table, [key.clone()])
	existing := defining(document, target)

	if existing.length() == 1:
		statement := document.statements[existing[0]]

		if statement.kind == TomlStatementKind.Pair and path_of(statement) == target:
			line := entry_text(statement.keys, value) + "\n"
			return assemble(
				splice(
					document.text,
					statement.start,
					statement.end,
					line,
				),
				document.crlf,
			)

	var current = document.clone()
	if not existing.is_empty(): current = remove_key(current, table, key)?

	entry := entry_text([key.clone()], value) + "\n"
	body := header_body_end(current, table)
	if body >= 0: return insert_after(current, body, entry)

	home := dotted_home(current, table)

	if home >= 0:
		statement := current.statements[home]
		parts := (
			statement.keys.length()
			- (path_of(statement).length() - table.length())
		)
		var keys = List[String]()
		for i in 0..parts: keys.append(statement.keys[i].clone())
		keys.append(key.clone())
		return insert_after(current, home, entry_text(keys, value) + "\n")

	sub := first_sub_table(current, table)

	if sub >= 0:
		start := current.statements[sub].start
		text := f"[{dotted(table)}]\n" + entry + "\n"
		return assemble(splice(current.text, start, start, text), current.crlf)

	if current.statements.is_empty():
		text := f"[{dotted(table)}]\n" + entry
		return assemble(text + current.text, current.crlf)

	last := current.statements.length() - 1
	return insert_after(current, last, f"\n[{dotted(table)}]\n" + entry)

// `value` with `key` removed from the table at `path[at..]` inside it.
fn without_key(value: TomlValue, path: List[String], at: Int, key: String) TomlValue:
	match value:
		TableValue(entries):
			var out = Map[String, TomlValue]()

			for entry in entries.entries():
				if at == path.length() and entry.key == key: continue

				if at < path.length() and entry.key == path[at]:
					out.add(
						entry.key.clone(),
						without_key(
							entry.value.clone(),
							path,
							at + 1,
							key,
						),
					)
				else:
					out.add(entry.key.clone(), entry.value.clone())

			return TomlValue.TableValue(out)
		_: return value.clone()

// `document` without `key` in `table`, and without `table` itself when that leaves it
// empty. An error when the key is not there.
export fn remove_key(
	document: TomlDocument,
	table: List[String],
	key: String,
) TomlDocument!:
	target := joined(table, [key.clone()])
	if value_at(document, target).is_none(): return error(
		invalid(f"{dotted(target)} is not in the document")
	)

	holder := inline_holder(document, table)

	if holder >= 0:
		statement := document.statements[holder]
		path := path_of(statement)

		if value := value_at(document, path):
			rest := table.slice(path.length(), table.length())?
			rebuilt := without_key(value, rest, 0, key)

			empty := match rebuilt:
				TableValue(entries): entries.is_empty()
				_: false

			if empty and rest.is_empty(): return without_statements(document, [holder])

			line := entry_text(statement.keys, rebuilt) + "\n"
			return assemble(
				splice(
					document.text,
					statement.start,
					statement.end,
					line,
				),
				document.crlf,
			)

	var indexes = defining(document, target)
	trimmed := without_statements(document, indexes)?

	// A header left with no statement under it goes too.
	var lone = -1

	for i in 0..trimmed.statements.length():
		statement := trimmed.statements[i]
		if statement.kind == TomlStatementKind.Header and statement.table == table: lone = i

	if lone < 0 or table.is_empty(): return ok(trimmed)

	for statement in trimmed.statements.clone():
		if (
			path_of(statement).length() > table.length()
			and starts_with(path_of(statement), table)
		):
			return ok(trimmed)
	return without_statements(trimmed, [lone])
