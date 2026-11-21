// Unused imports (MSL102) and the edit that removes each. A name counts as used when it
// is written anywhere outside the imports as a name or a type; a list, map or decimal
// literal uses the prelude names `List`, `Map` and `Decimal` even where none is
// written. Spelling decides, not resolution, so a local that shadows an import hides
// the import's disuse and never reports a used one.
import (
	Bytes from "@std/bytes.ms",
	expect_equal from "@std/test/test.ms",

	Syntax, Token, children, lex, node_kind, parse, token_kind from "../syntax.ms",
	Finding, finding, with_fix from "./finding.ms",
)

// One bound name of an import: where its statement, clause and name begin.
type Binding:
	name: String
	statement: Int
	clause: Int
	at: Int
	line: Int
	column: Int

fn name_of(tree: Syntax, at: Int) String:
	index := tree.a[at]
	if index < 0: return ""

	return tree.names[index].clone()

fn bindings(tree: Syntax) List[Binding]:
	var out = List[Binding]()
	import_kind := node_kind("Import")

	for at in children(tree, 0):
		if tree.kind[at] != import_kind: continue

		parts := children(tree, at)
		out.append(
			Binding(
				name: name_of(tree, at),
				statement: tree.offset[at],
				clause: tree.offset[parts[0]],
				at: tree.offset[parts[1]],
				line: tree.line[parts[1]],
				column: tree.column[parts[1]],
			)
		)

	return out

// The names a module uses outside its imports.
fn used_names(tree: Syntax) Set[String]:
	var used = Set[String]()
	name := node_kind("Name")
	named := node_kind("TypeNamed")
	list := node_kind("ListExpr")
	map := node_kind("Map")
	number := node_kind("Number")

	for at in 0..tree.kind.length():
		kind := tree.kind[at]

		if kind == name or kind == named: used.add(name_of(tree, at))
		else if kind == list: used.add("List")
		else if kind == map: used.add("Map")
		else if kind == number:
			spelling := name_of(tree, at)
			if spelling.ends_with("d") and not spelling.starts_with("0x"): used.add(
				"Decimal"
			)

	return used

fn is_blank(byte: UInt8) Bool: byte == 32 or byte == 9

fn skip_blanks(source: Bytes, from: Int) Int:
	var at = from
	while at < source.length() and is_blank(source[at]): at += 1
	return at

// The start of the line holding byte `at`.
fn line_start(source: Bytes, at: Int) Int:
	var start = at
	while start > 0 and source[start - 1] != 10: start -= 1
	return start

// Whether `source[from..to]` is only blanks, carriage returns and line breaks.
fn only_space(source: Bytes, from: Int, to: Int) Bool:
	for at in from..to:
		byte := source[at]
		if not (is_blank(byte) or byte == 10 or byte == 13): return false

	return true

// The first token at or after byte `offset`.
fn first_token(tokens: List[Token], offset: Int) Int:
	var at = 0
	while at < tokens.length() and tokens[at].offset < offset: at += 1
	return at

// Whether the statement at `statement` holds a group of clauses: `import (A from "a")`.
fn in_group(source: Bytes, tokens: List[Token], statement: Int) Bool:
	first := first_token(tokens, statement)
	if first + 1 >= tokens.length() or tokens[first + 1].kind != token_kind("("): return false

	for at in first + 2..tokens.length():
		token := tokens[at]
		if token.kind == token_kind(")"): return false
		if (
			token.kind == token_kind("NAME")
			and source.view(
				token.offset,
				token.end_offset,
			) == "from".to_bytes()
		): return true

	return false

// The byte range that deletes a clause from a grouped import, or the whole statement
// when `whole` is set. It takes the clause's trailing comma and, when the clause is
// alone on its line, the line itself. `end` is -1 when the tokens do not close the
// group.
fn group_removal(
	source: Bytes,
	tokens: List[Token],
	binding: Binding,
	whole: Bool,
	var range: List[Int],
) Void:
	start := if whole: binding.statement else: binding.clause
	first := first_token(tokens, binding.statement)
	var end = -1

	if whole:
		var depth = 0

		for at in first + 1..tokens.length():
			kind := tokens[at].kind

			if kind == token_kind("("): depth += 1
			else if kind == token_kind(")"):
				depth -= 1
				if depth < 0: return

				if depth == 0:
					end = tokens[at].end_offset
					break
	else:
		var at = first_token(tokens, binding.clause)
		while at < tokens.length() and tokens[at].kind != token_kind("STRING"): at += 1
		if at == tokens.length(): return

		end = skip_blanks(source, tokens[at].end_offset)
		if end < source.length() and source[end] == 44: end += 1

	if end < 0: return

	begin := line_start(source, start)
	var stop = end
	while stop < source.length() and source[stop] != 10: stop += 1

	if only_space(source, begin, start) and only_space(source, end, stop):
		if stop < source.length(): stop += 1
		range.append(begin)
		range.append(stop)
		return

	range.append(start)
	range.append(end)

// Deletes a whole `import ... from "path"` statement, with its line break.
fn statement_removal(
	source: Bytes,
	tokens: List[Token],
	binding: Binding,
	var range: List[Int],
) Void:
	var at = first_token(tokens, binding.statement)
	while at < tokens.length() and tokens[at].kind != token_kind("STRING"): at += 1
	if at == tokens.length(): return

	var line_end = tokens[at].end_offset
	while line_end < source.length() and source[line_end] != 10: line_end += 1
	if line_end < source.length(): line_end += 1

	begin := line_start(source, binding.statement)

	if only_space(source, begin, binding.statement): range.append(begin)
	else: range.append(binding.statement)

	range.append(line_end)

// Deletes one name and its separator from an import list that keeps other names.
fn name_removal(source: Bytes, binding: Binding, var range: List[Int]) Void:
	start := binding.at
	end := start + binding.name.length()
	after := skip_blanks(source, end)

	if after < source.length() and source[after] == 44:
		next := skip_blanks(source, after + 1)
		begin := line_start(source, start)
		var newline = 0

		if next + 1 < source.length() and source[next] == 13 and source[next + 1] == 10: newline = 2
		else if next < source.length() and source[next] == 10: newline = 1

		if newline > 0 and only_space(source, begin, start):
			range.append(begin)
			range.append(next + newline)
		else:
			range.append(start)
			range.append(next)

		return

	var before = start
	while before > 0 and is_blank(source[before - 1]): before -= 1
	if before == 0 or source[before - 1] != 44: return

	range.append(before - 1)
	range.append(end)

// The findings for the imports of the module in `text`; none when it does not parse.
export fn lint_imports(file: String, text: String) List[Finding]:
	var out = List[Finding]()
	parsed := parse(text)
	if parsed.is_error(): return out

	tree := parsed.get()
	all := bindings(tree)
	used := used_names(tree)
	source := text.to_bytes()
	tokens := lex(text).get_or([])

	for binding in all:
		if used.contains(binding.name): continue

		whole := all.all(
			fn other: (
				other.clause != binding.clause
				or not used.contains(other.name)
			)
		)
		statement_unused := all.all(
			fn other: (
				other.statement != binding.statement
				or not used.contains(other.name)
			)
		)
		grouped := whole and in_group(source, tokens, binding.statement)
		var range = List[Int]()

		if grouped: group_removal(source, tokens, binding, statement_unused, range)
		else if whole: statement_removal(source, tokens, binding, range)
		else: name_removal(source, binding, range)

		found := finding(
			"MSL102",
			"warning",
			f"Import {binding.name} is never used",
			file,
			binding.at,
			binding.line,
			binding.column,
		)

		if range.length() == 2: out.append(with_fix(found, range[0], range[1], ""))
		else: out.append(found)

	return out

test "an unused import is reported with the edit that removes it":
	source := "import (\n\tA, B from \"a\",\n\tC from \"c\",\n)\nimport D from \"d\"\nx := A(C)\n"
	found := lint_imports("t.ms", source)
	found.length() | expect_equal(expected: 2)?
	found[0].message | expect_equal(expected: "Import B is never used")?
	found[1].message | expect_equal(expected: "Import D is never used")?
	found[1].fix_from | expect_equal(expected: 40)?
