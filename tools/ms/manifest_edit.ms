// Edits to `ms.toml` for `ms add` and `ms remove`: they change the `[dependencies]` and
// `[effects]` tables and keep every comment and the formatting of the rest of the file.
//
// `parse` (the stdlib TOML parser) says whether the manifest is valid and what it holds;
// the edit itself works on lines, because a parsed value forgets comments and layout. A
// comment or blank line belongs to the item that follows it: removing an entry removes
// the comments above it, and a new table goes after the last item of the file, before
// its trailing comments. A manifest that spreads a value over several lines, or writes
// `dependencies` or `effects` as dotted keys or sub-tables, is an error that asks for a
// hand edit.
import (
	TomlValue, parse from "@std/data/toml.ms",
	expect_equal from "@std/test/test.ms",
)

// How a dependency pins its source.
export enum Pin:
	Tag(value: String)
	Sha(value: String)
	Version(value: String)

BLANK := 0
COMMENT := 1
HEADER := 2
KEY := 3

type Line:
	text: String
	kind: Int
	// A header's table, or a key's name.
	name: String
	// The table a key is in; empty before the first header.
	table: String

type Key:
	name: String
	// The text after the `=`.
	value: String

fn fail(message: String) Error:
	return Error(message)

fn bare_scalar(scalar: Int) Bool:
	return (
		(scalar >= 97 and scalar <= 122)
		or (scalar >= 65 and scalar <= 90)
		or (scalar >= 48 and scalar <= 57)
		or scalar == 45
		or scalar == 95
	)

// `@name`: `@`, then letters, digits and underscores, the first not a digit.
export fn valid_alias(key: String) Bool:
	if not key.starts_with("@") or key.length() < 2: return false

	var index = 0

	for scalar in key.slice(1, key.length()).scalar_values():
		letter := (
			(scalar >= 97 and scalar <= 122)
			or (scalar >= 65 and scalar <= 90)
			or scalar == 95
		)
		digit := scalar >= 48 and scalar <= 57
		if not letter and not (digit and index > 0): return false

		index += 1

	return true

// The package name `ms add` gives a repository URL: its last path segment without
// `.git` and without a leading `ms-`, so `https://github.com/acme/ms-pg.git` is `@pg`.
export fn default_name(url: String) String?:
	var trimmed = url.clone()
	while trimmed.ends_with("/"):
		trimmed = trimmed.slice(0, trimmed.length() - 1)

	var start = 0
	if slash := trimmed.last_index_of("/"): start = slash + 1
	if colon := trimmed.last_index_of(":"):
		if colon + 1 > start: start = colon + 1

	var base = trimmed.slice(start, trimmed.length())
	if cut := base.cut_suffix(".git"): base = cut
	if cut := base.cut_prefix("ms-"): base = cut

	name := "@" + base.replace("-", "_")
	if valid_alias(name): return name

	return none

// A TOML basic string for `text`; text that would need an escape is refused.
fn quote(text: String) String!:
	if (
		text.contains("\"")
		or text.contains("\\")
		or text.find_char(
			fn c: c.scalar_at(0) < 32 or c.scalar_at(0) == 127
		).is_some()
	): return error(
		fail(
			f"{text} cannot be written to ms.toml without an escape; edit ms.toml by hand"
		)
	)
	return ok("\"" + text + "\"")

fn key_text(name: String) String!:
	for scalar in name.scalar_values():
		if not bare_scalar(scalar): return quote(name)
	if name.is_empty(): return quote(name)

	return ok(name.clone())

// The key at the start of `text` and the text after its `=`; none for text that is not
// a complete `key = value` line.
fn read_key(text: String) Key?:
	var name = ""
	var rest = text.clone()

	if text.starts_with("\""):
		found := text.slice(1, text.length()).index_of("\"")
		close := found.get_or(-1)
		if close < 0: return none

		name = text.slice(1, 1 + close)
		if name.contains("\\"): return none

		rest = text.slice(close + 2, text.length())

		// A dotted key after a quoted part; only its first part matters here.
		if rest.trim().starts_with("."): name += "."
	else:
		at := text.index_of("=").get_or(-1)
		if at < 0: return none

		name = text.slice(0, at).trim()
		rest = text.slice(at, text.length())

	eq := rest.index_of("=").get_or(-1)
	if eq < 0: return none

	return Key(name, rest.slice(eq + 1, rest.length()))

// Whether a value's text ends on its line: its strings are closed and its brackets
// balanced.
fn value_complete(value: String) Bool:
	data := value.as_bytes()
	var depth = 0
	var i = 0

	while i < data.length():
		b := data.get(i).to_int()

		if b == 34 or b == 39:
			i += 1

			while i < data.length() and data.get(i).to_int() != b:
				if b == 34 and data.get(i).to_int() == 92: i += 1
				i += 1

			if i >= data.length(): return false
		else if b == 35:
			break
		else if b == 91 or b == 123:
			depth += 1
		else if b == 93 or b == 125:
			depth -= 1

		i += 1

	return depth == 0

fn unreadable(text: String) Error:
	return fail(
		f"ms.toml has a line the manifest editor cannot place ({text.trim()}); edit ms.toml by hand"
	)

fn scan(text: String, table: String) Line!:
	body := text.trim()
	if body.is_empty(): return ok(Line(text.clone(), BLANK, "", table.clone()))
	if body.starts_with("#"): return ok(Line(text.clone(), COMMENT, "", table.clone()))
	if body.starts_with("[["): return ok(
		Line(text.clone(), HEADER, body.clone(), table.clone())
	)

	if body.starts_with("["):
		close := body.index_of("]").get_or(-1)
		if close < 0: return error(unreadable(text))

		var name = body.slice(1, close).trim()
		tail := body.slice(close + 1, body.length()).trim()
		if not tail.is_empty() and not tail.starts_with("#"): return error(
			unreadable(text)
		)

		if name.length() >= 2 and name.starts_with("\"") and name.ends_with("\""):
			name = name.slice(1, name.length() - 1)
		return ok(Line(text.clone(), HEADER, name, table.clone()))

	if key := read_key(body):
		if value_complete(key.value): return ok(
			Line(text.clone(), KEY, key.name.clone(), table.clone())
		)
	return error(unreadable(text))

fn dotted_into(name: String, table: String) Bool:
	return name == table or name.starts_with(table + ".")

fn split_lines(text: String) List[Line]!:
	var lines = List[Line]()
	if text.is_empty(): return ok(lines)

	pieces := text.split("\n")
	var count = pieces.length()
	if text.ends_with("\n"): count -= 1

	var table = ""

	for i in 0..count:
		line := scan(pieces[i].clone(), table.clone())?
		if line.kind == HEADER: table = line.name.clone()

		for owned in ["dependencies", "effects"]:
			sub := (
				(
					line.kind == HEADER
					and line.name.starts_with(owned + ".")
				)
				or (
					line.kind == KEY
					and line.table.is_empty()
					and dotted_into(line.name, owned)
				)
			)
			if sub: return error(
				fail(
					f"ms.toml writes [{owned}] in a form the manifest editor cannot change; edit ms.toml by hand"
				)
			)

		lines.append(line)

	return ok(lines)

// The header line of table `name`, or -1.
fn find_table(lines: List[Line], name: String) Int:
	for i in 0..lines.length():
		if lines[i].kind == HEADER and lines[i].name == name: return i
	return -1

// The line of the last entry of the table at `header`, or the header when it has none.
fn last_entry(lines: List[Line], header: Int) Int:
	var last = header
	var i = header + 1

	while i < lines.length() and lines[i].kind != HEADER:
		if lines[i].kind == KEY: last = i
		i += 1

	return last

fn find_key(lines: List[Line], header: Int, name: String) Int:
	var i = header + 1

	while i < lines.length() and lines[i].kind != HEADER:
		if lines[i].kind == KEY and lines[i].name == name: return i

		i += 1

	return -1

fn entry_count(lines: List[Line], dropped: List[Bool], header: Int) Int:
	var count = 0
	var i = header + 1

	while i < lines.length() and lines[i].kind != HEADER:
		if lines[i].kind == KEY and not dropped[i]: count += 1
		i += 1

	return count

// Marks line `index` and the blank and comment lines just above it, which belong to it.
fn drop_with_prefix(lines: List[Line], var dropped: List[Bool], index: Int) Void:
	var first = index
	while (
		first > 0
		and (lines[first - 1].kind == BLANK or lines[first - 1].kind == COMMENT)
	):
		first -= 1
	for i in first..(index + 1): dropped[i] = true

fn joined(parts: List[String]) String:
	if parts.is_empty(): return ""
	return parts.join("\n") + "\n"

// The lines with `entry` added to table `name` (its header at `header`, or -1 to create
// the table after the last item of the file); `replace` is the line `entry` takes the
// place of, or -1.
fn insert_entry(
	lines: List[Line],
	header: Int,
	name: String,
	entry: String,
	replace: Int,
) String!:
	var content = -1
	for i in 0..lines.length():
		if lines[i].kind == HEADER or lines[i].kind == KEY: content = i
	if header < 0 and content < 0 and not lines.is_empty(): return error(
		fail("ms.toml holds only comments; add a [project] table first")
	)

	after := if header >= 0 and replace < 0: last_entry(lines, header) else: -1
	var out = List[String]()

	if lines.is_empty():
		out.append(f"[{name}]")
		out.append(entry.clone())

	for i in 0..lines.length():
		out.append(if i == replace: entry.clone() else: lines[i].text.clone())
		if i == after: out.append(entry.clone())

		if header < 0 and i == content:
			out.append("")
			out.append(f"[{name}]")
			out.append(entry.clone())

	return ok(joined(out))

fn table_of(value: TomlValue, key: String) TomlValue?:
	match value:
		TableValue(entries): return entries.get(key)
		_: return none

// The parsed manifest, with `name` checked to be a table when present. Returns the
// table (none when absent).
fn read_table(document: TomlValue, name: String) TomlValue?!:
	if found := table_of(document, name):
		match found:
			TableValue(_): return ok(found.clone())
			_: return error(fail(f"[{name}] in ms.toml is not a table"))

	return ok(none)

fn holds(key: String, table: TomlValue?) Bool:
	if found := table: return table_of(found, key).is_some()
	return false

fn read_manifest(text: String) TomlValue!:
	document := parse(text)
	if document.is_error(): return error(
		fail(f"ms.toml is not valid TOML: {document.err().message}")
	)

	return ok(document.get())

// `text` in LF, and whether it was CRLF.
fn normalise(text: String) String:
	return text.replace("\r\n", "\n")

fn restore(text: String, crlf: Bool) String:
	if crlf: return text.replace("\n", "\r\n")
	return text.clone()

// `text` with `name = { url = ..., version | tag | sha = ... }` under `[dependencies]`.
export fn add_dependency(text: String, name: String, url: String, pin: Pin) String!:
	plain := normalise(text)
	document := read_manifest(plain)?
	dependencies := read_table(document, "dependencies")?
	if holds(name, dependencies): return error(
		fail(
			f"{name} is already in [dependencies]; run `ms remove {name}` first, or edit its entry"
		)
	)

	var pin_key = "tag"
	var pinned = ""

	match pin:
		Tag(value):
			pinned = value.clone()
		Sha(value):
			pin_key = "sha"
			pinned = value.clone()
		Version(value):
			pin_key = "version"
			pinned = value.clone()

	lines := split_lines(plain)?
	entry := (
		key_text(name)?
		+ " = { url = "
		+ quote(url)?
		+ ", "
		+ pin_key
		+ " = "
		+ quote(pinned)?
		+ " }"
	)
	edited := insert_entry(
		lines,
		find_table(lines, "dependencies"),
		"dependencies",
		entry,
		-1,
	)?
	return ok(restore(edited, text.contains("\r\n")))

// `text` allowing `name` the `effects` it declares, under `[effects]`.
export fn allow_effects(text: String, name: String, effects: List[String]) String!:
	plain := normalise(text)
	document := read_manifest(plain)?
	_effects := read_table(document, "effects")?
	var quoted = List[String]()
	for effect in effects: quoted.append(quote(effect)?)

	lines := split_lines(plain)?
	header := find_table(lines, "effects")
	existing := if header >= 0: find_key(lines, header, name) else: -1
	if existing >= 0 and lines[existing].text.contains("#"): return error(
		fail(
			"an [effects] entry with a comment cannot be replaced; edit ms.toml by hand"
		)
	)

	entry := key_text(name)? + " = [" + quoted.join(", ") + "]"
	edited := insert_entry(lines, header, "effects", entry, existing)?
	return ok(restore(edited, text.contains("\r\n")))

// Drops `name` from the table at `header` and, when that leaves it empty, the table.
fn drop_entry(
	lines: List[Line],
	var dropped: List[Bool],
	header: Int,
	name: String,
) Void:
	key := find_key(lines, header, name)
	if key >= 0: drop_with_prefix(lines, dropped, key)
	if entry_count(lines, dropped, header) == 0: drop_with_prefix(
		lines,
		dropped,
		header,
	)

// `text` without `name` in `[dependencies]` and `[effects]`; an error when it was not a
// dependency.
export fn remove_dependency(text: String, name: String) String!:
	plain := normalise(text)
	document := read_manifest(plain)?
	dependencies := read_table(document, "dependencies")?
	_effects := read_table(document, "effects")?
	if not holds(name, dependencies): return error(
		fail(f"{name} is not in [dependencies]")
	)

	lines := split_lines(plain)?
	header := find_table(lines, "dependencies")
	if header < 0 or find_key(lines, header, name) < 0: return error(
		fail(
			f"{name} is written in a form the manifest editor cannot change; edit ms.toml by hand"
		)
	)

	var dropped = List[Bool]()
	for _line in lines: dropped.append(false)
	drop_entry(lines, dropped, header, name)

	effects := find_table(lines, "effects")
	if effects >= 0: drop_entry(lines, dropped, effects, name)

	var kept = List[String]()
	for i in 0..lines.length():
		if not dropped[i]: kept.append(lines[i].text.clone())
	return ok(restore(joined(kept), text.contains("\r\n")))

URL := "https://h/x/ms-pg.git"
PROJECT := "[project]\nname = \"a\"\nsource = \"src\"\n"
PG := "\"@pg\" = { url = \"https://h/x/ms-pg.git\", tag = \"v1\" }\n"
DEP_A := "\"@a\" = { url = \"https://h/a.git\", tag = \"v1\" }"
WITH := (
	PROJECT
	+ "\n[dependencies]\n"
	+ DEP_A
	+ " # note\n\n[effects]\n\"@a\" = [\"std.net.*\"]\n"
)

test "a dependency is added after the last item, keeping comments":
	base := "# my app\n[project]\nname = \"app\" # the name\nsource = \"src\"\n"
	expect_equal(
		add_dependency(base, "@pg", URL, Pin.Tag("v1.0.0"))?,
		"# my app\n[project]\nname = \"app\" # the name\nsource = \"src\"\n\n[dependencies]\n\"@pg\" = { url = \"https://h/x/ms-pg.git\", tag = \"v1.0.0\" }\n",
	)?
	expect_equal(
		add_dependency(
			"[project]\nname = \"a\"\nsource = \"src\"",
			"@pg",
			URL,
			Pin.Version("^1.2"),
		)?,
		PROJECT
		+ "\n[dependencies]\n\"@pg\" = { url = \"https://h/x/ms-pg.git\", version = \"^1.2\" }\n",
	)?
	expect_equal(
		add_dependency(PROJECT + "\n", "@pg", URL, Pin.Sha("aaaa"))?,
		PROJECT
		+ "\n[dependencies]\n\"@pg\" = { url = \"https://h/x/ms-pg.git\", sha = \"aaaa\" }\n\n",
	)?
	expect_equal(
		add_dependency(WITH, "@pg", URL, Pin.Tag("v1"))?,
		PROJECT
		+ "\n[dependencies]\n"
		+ DEP_A
		+ " # note\n"
		+ PG
		+ "\n[effects]\n\"@a\" = [\"std.net.*\"]\n",
	)?
	expect_equal(
		add_dependency(
			"[project]\nname = \"a\"\n# end\n",
			"@pg",
			URL,
			Pin.Tag("v1"),
		)?,
		"[project]\nname = \"a\"\n\n[dependencies]\n" + PG + "# end\n",
	)?
	expect_equal(
		add_dependency("", "@pg", URL, Pin.Tag("v1"))?,
		"[dependencies]\n" + PG,
	)?
	expect_equal(
		add_dependency("[project]\nname=\"a\"\n", "pg", URL, Pin.Tag("v1"))?,
		"[project]\nname=\"a\"\n\n[dependencies]\npg = { url = \"https://h/x/ms-pg.git\", tag = \"v1\" }\n",
	)?

test "a dependency goes into an existing table where its entries end":
	expect_equal(
		add_dependency(
			PROJECT + "[dependencies]\n",
			"@pg",
			URL,
			Pin.Tag("v1"),
		)?,
		PROJECT + "[dependencies]\n" + PG,
	)?
	expect_equal(
		add_dependency(
			"[project]\nname = \"a\"\n[dependencies]\n\"@a\" = { url = \"u\", tag = \"v\" }\n[aliases]\n\"@x\" = \"src\"\n",
			"@pg",
			URL,
			Pin.Tag("v1"),
		)?,
		"[project]\nname = \"a\"\n[dependencies]\n\"@a\" = { url = \"u\", tag = \"v\" }\n"
		+ PG
		+ "[aliases]\n\"@x\" = \"src\"\n",
	)?
	expect_equal(
		add_dependency(
			"[project]\nname = \"a\"\n[dependencies] # d\n",
			"@pg",
			URL,
			Pin.Tag("v1"),
		)?,
		"[project]\nname = \"a\"\n[dependencies] # d\n" + PG,
	)?
	expect_equal(
		add_dependency(
			"[project]\nname = \"a\"\n[aliases]\n\"@x\" = \"src\"\n[embed]\n\"@e\" = \"d\"\n",
			"@pg",
			URL,
			Pin.Tag("v1"),
		)?,
		"[project]\nname = \"a\"\n[aliases]\n\"@x\" = \"src\"\n[embed]\n\"@e\" = \"d\"\n\n[dependencies]\n"
		+ PG,
	)?

test "a CRLF manifest stays CRLF":
	expect_equal(
		add_dependency(
			"# my app\r\n[project]\r\nname = \"a\"\r\n",
			"@pg",
			URL,
			Pin.Tag("v1"),
		)?,
		"# my app\r\n[project]\r\nname = \"a\"\r\n\r\n[dependencies]\r\n\"@pg\" = { url = \"https://h/x/ms-pg.git\", tag = \"v1\" }\r\n",
	)?
	expect_equal(
		remove_dependency(
			"[project]\r\nname = \"a\"\r\n\r\n[dependencies]\r\n" + DEP_A + "\r\n",
			"@a",
		)?,
		"[project]\r\nname = \"a\"\r\n",
	)?

test "adding refuses a repeat, bad TOML and forms it cannot place":
	expect_equal(
		add_dependency(WITH, "@a", URL, Pin.Tag("v1")).err().message,
		"@a is already in [dependencies]; run `ms remove @a` first, or edit its entry",
	)?
	expect_equal(
		add_dependency(
			"[project\n",
			"@pg",
			URL,
			Pin.Tag("v1"),
		).err().message.starts_with("ms.toml is not valid TOML: "),
		true,
	)?
	expect_equal(
		add_dependency(
			"dependencies = 3\n",
			"@pg",
			URL,
			Pin.Tag("v1"),
		).err().message,
		"[dependencies] in ms.toml is not a table",
	)?
	expect_equal(
		add_dependency(
			PROJECT + "[dependencies.x]\nurl = \"u\"\n",
			"@pg",
			URL,
			Pin.Tag("v1"),
		).is_error(),
		true,
	)?
	expect_equal(
		add_dependency(
			"[project]\nname = \"a\"\nlist = [\n\t1,\n]\n",
			"@pg",
			URL,
			Pin.Tag("v1"),
		).is_error(),
		true,
	)?

test "effects are allowed in a new or existing table":
	expect_equal(
		allow_effects(
			"# my app\n[project]\nname = \"app\" # the name\nsource = \"src\"\n",
			"@pg",
			["std.net.*"],
		)?,
		"# my app\n[project]\nname = \"app\" # the name\nsource = \"src\"\n\n[effects]\n\"@pg\" = [\"std.net.*\"]\n",
	)?
	expect_equal(
		allow_effects(WITH, "@pg", ["std.fs.read", "std.net.*"])?,
		PROJECT
		+ "\n[dependencies]\n"
		+ DEP_A
		+ " # note\n\n[effects]\n\"@a\" = [\"std.net.*\"]\n\"@pg\" = [\"std.fs.read\", \"std.net.*\"]\n",
	)?
	expect_equal(
		allow_effects(WITH, "@a", ["std.fs.read"])?,
		PROJECT
		+ "\n[dependencies]\n"
		+ DEP_A
		+ " # note\n\n[effects]\n\"@a\" = [\"std.fs.read\"]\n",
	)?
	expect_equal(
		allow_effects("[effects]\n[project]\nname=\"a\"\n", "@pg", ["x"])?,
		"[effects]\n\"@pg\" = [\"x\"]\n[project]\nname=\"a\"\n",
	)?

test "removing takes the entry, its comments and an emptied table":
	expect_equal(remove_dependency(WITH, "@a")?, PROJECT)?
	expect_equal(
		remove_dependency(WITH, "@zz").err().message,
		"@zz is not in [dependencies]",
	)?

	pair := (
		PROJECT
		+ "[dependencies]\n"
		+ DEP_A
		+ "\n\"@b\" = { url = \"https://h/b.git\", tag = \"v1\" }\n"
	)
	expect_equal(
		remove_dependency(pair, "@a")?,
		PROJECT
		+ "[dependencies]\n\"@b\" = { url = \"https://h/b.git\", tag = \"v1\" }\n",
	)?
	expect_equal(
		remove_dependency(PROJECT + "\n[dependencies]\n" + DEP_A + "\n", "@a")?,
		PROJECT,
	)?

	notes := "[project]\nname = \"a\"\n[dependencies]\n# about a\n\"@a\" = { url = \"u\", tag = \"v\" }\n# about b\n\n\"@b\" = { url = \"u\", tag = \"v\" }\n[aliases]\n\"@x\" = \"s\"\n"
	expect_equal(
		remove_dependency(notes, "@a")?,
		"[project]\nname = \"a\"\n[dependencies]\n# about b\n\n\"@b\" = { url = \"u\", tag = \"v\" }\n[aliases]\n\"@x\" = \"s\"\n",
	)?
	expect_equal(
		remove_dependency(notes, "@b")?,
		"[project]\nname = \"a\"\n[dependencies]\n# about a\n\"@a\" = { url = \"u\", tag = \"v\" }\n[aliases]\n\"@x\" = \"s\"\n",
	)?
	expect_equal(
		remove_dependency(
			"[project]\nname = \"a\"\n\n# deps\n[dependencies]\n# about a\n\"@a\" = { url = \"u\", tag = \"v\" }\n\n# al\n[aliases]\n\"@x\" = \"s\"\n# end\n",
			"@a",
		)?,
		"[project]\nname = \"a\"\n\n# al\n[aliases]\n\"@x\" = \"s\"\n# end\n",
	)?

test "package names come from the repository":
	expect_equal(default_name("https://github.com/acme/ms-pg.git"), "@pg")?
	expect_equal(default_name("https://github.com/acme/wire/"), "@wire")?
	expect_equal(default_name("https://github.com/acme/my-lib.git"), "@my_lib")?
	expect_equal(default_name("git@h:acme/x.git"), "@x")?
	expect_equal(default_name("file:///tmp/r"), "@r")?
	expect_equal(default_name("https://github.com/acme/2fast.git").is_none(), true)?
