// Edits to `ms.toml` for `ms add` and `ms remove`: they change the `[dependencies]` and
// `[effects]` tables and keep every comment and the formatting of the rest of the file.
// The edits are `set_key` and `remove_key` on a `TomlDocument`
// (`@std/data/toml_edit.ms`), which reads layout from the stdlib TOML parser, so every
// way TOML can write the tables (headers, sub-tables, dotted keys, multi-line values)
// is handled the same way.
import (
	TomlValue from "@std/data/toml.ms",
	TomlDocument,
	is_inline_table,
	parse_document,
	remove_key,
	set_key,
	to_string,
	value_at from "@std/data/toml_edit.ms",
	expect_equal from "@std/test/test.ms",
)

// How a dependency pins its source.
export enum Pin:
	Tag(value: String)
	Sha(value: String)
	Version(value: String)

fn fail(message: String) Error:
	return Error(message)

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

fn read_manifest(text: String) TomlDocument!:
	document := parse_document(text)
	if document.is_error(): return error(
		fail(f"ms.toml is not valid TOML: {document.err().message}")
	)

	return ok(document.get())

// Checks that `name` is a table when the manifest has it, and not an inline table,
// which the editor does not change.
fn require_table(document: TomlDocument, name: String, inline_ok: Bool) Void!:
	if found := value_at(document, [name.clone()]):
		match found:
			TableValue(_):
				if not inline_ok and is_inline_table(document, [name.clone()]): return error(
					fail(f"[{name}] in ms.toml is not a table")
				)
			_: return error(fail(f"[{name}] in ms.toml is not a table"))

	return ok()

fn text_value(text: String) TomlValue:
	return TomlValue.StringValue(text)

fn same_table(entries: List[List[String]]) TomlValue:
	var table = Map[String, TomlValue]()
	for entry in entries: table.add(entry[0].clone(), text_value(entry[1].clone()))
	return TomlValue.TableValue(table)

// `text` with `name = { url = ..., version | tag | sha = ... }` under `[dependencies]`.
export fn add_dependency(text: String, name: String, url: String, pin: Pin) String!:
	document := read_manifest(text)?
	require_table(document, "dependencies", false)?
	if value_at(document, ["dependencies", name.clone()]).is_some(): return error(
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

	entry := same_table([["url", url.clone()], [pin_key, pinned]])
	edited := set_key(document, ["dependencies"], name, entry)?
	return ok(to_string(edited))

// `text` allowing `name` the `effects` it declares, under `[effects]`.
export fn allow_effects(text: String, name: String, effects: List[String]) String!:
	document := read_manifest(text)?
	require_table(document, "effects", false)?

	var allowed = List[TomlValue]()
	for effect in effects.clone(): allowed.append(text_value(effect))

	edited := set_key(document, ["effects"], name, TomlValue.ArrayValue(allowed))?
	return ok(to_string(edited))

// `text` without `name` in `[dependencies]` and `[effects]`; an error when it was not a
// dependency.
export fn remove_dependency(text: String, name: String) String!:
	document := read_manifest(text)?
	require_table(document, "dependencies", true)?
	require_table(document, "effects", true)?
	if value_at(document, ["dependencies", name.clone()]).is_none(): return error(
		fail(f"{name} is not in [dependencies]")
	)

	var edited = remove_key(document, ["dependencies"], name)?
	if value_at(edited, ["effects", name.clone()]).is_some(): edited = remove_key(
		edited,
		["effects"],
		name,
	)?
	return ok(to_string(edited))

URL := "https://h/x/ms-pg.git"
PROJECT := "[project]\nname = \"a\"\nsource = \"src\"\n"
PG := "\"@pg\" = { url = \"https://h/x/ms-pg.git\", tag = \"v1\" }\n"
DEP_A := "\"@a\" = { url = \"https://h/a.git\", tag = \"v1\" }"
INLINE := "dependencies = { \"@a\" = { url = \"u\", tag = \"v\" } }\n[project]\nname = \"a\"\n"
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

test "adding refuses a repeat, bad TOML and a table that is not a table":
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
		add_dependency(INLINE, "@pg", URL, Pin.Tag("v1")).err().message,
		"[dependencies] in ms.toml is not a table",
	)?

SUB := (
	PROJECT
	+ "\n[dependencies.\"@a\"]\nurl = \"u\"\ntag = \"v\"\n\n[aliases]\n\"@x\" = \"s\"\n"
)
TWO := (
	PROJECT
	+ "\n[dependencies.\"@a\"]\nurl = \"u\"\ntag = \"v\"\n\n[dependencies.\"@b\"]\nurl = \"u\"\ntag = \"v\"\n"
)
DOTTED := "dependencies.\"@a\" = { url = \"u\", tag = \"v\" }\n[project]\nname = \"a\"\n"
KEYED := "[project]\nname = \"a\"\n[dependencies]\n\"@a\".url = \"u\"\n\"@a\".tag = \"v\"\n[aliases]\n\"@x\" = \"s\"\n"
ML := "[project]\nname = \"a\"\nlist = [\n  1,\n  2,\n]\n[dependencies]\n\"@a\" = { url = \"u\", tag = \"v\" }\n[effects]\n\"@a\" = [\n  \"std.net.*\",\n  \"std.fs.read\", # c\n]\n"

test "dependencies written as sub-tables are added to and removed from":
	expect_equal(
		add_dependency(SUB, "@pg", URL, Pin.Tag("v1"))?,
		PROJECT
		+ "\n[dependencies]\n"
		+ PG
		+ "\n[dependencies.\"@a\"]\nurl = \"u\"\ntag = \"v\"\n\n[aliases]\n\"@x\" = \"s\"\n",
	)?
	expect_equal(
		remove_dependency(SUB, "@a")?,
		PROJECT + "\n[aliases]\n\"@x\" = \"s\"\n",
	)?
	expect_equal(
		remove_dependency(TWO, "@a")?,
		PROJECT + "\n[dependencies.\"@b\"]\nurl = \"u\"\ntag = \"v\"\n",
	)?

	both := (
		PROJECT
		+ "[dependencies]\n"
		+ DEP_A
		+ "\n[dependencies.\"@b\"]\nurl = \"u\"\ntag = \"v\"\n[aliases]\n\"@x\" = \"s\"\n"
	)
	expect_equal(
		add_dependency(both, "@pg", URL, Pin.Tag("v1"))?,
		PROJECT
		+ "[dependencies]\n"
		+ DEP_A
		+ "\n"
		+ PG
		+ "[dependencies.\"@b\"]\nurl = \"u\"\ntag = \"v\"\n[aliases]\n\"@x\" = \"s\"\n",
	)?
	expect_equal(
		remove_dependency(both, "@b")?,
		PROJECT + "[dependencies]\n" + DEP_A + "\n[aliases]\n\"@x\" = \"s\"\n",
	)?

test "dependencies written as dotted keys are added to and removed from":
	expect_equal(
		add_dependency(DOTTED, "@pg", URL, Pin.Tag("v1"))?,
		"dependencies.\"@a\" = { url = \"u\", tag = \"v\" }\ndependencies.\"@pg\" = { url = \"https://h/x/ms-pg.git\", tag = \"v1\" }\n[project]\nname = \"a\"\n",
	)?
	expect_equal(remove_dependency(DOTTED, "@a")?, "[project]\nname = \"a\"\n")?
	expect_equal(
		add_dependency(KEYED, "@pg", URL, Pin.Tag("v1"))?,
		"[project]\nname = \"a\"\n[dependencies]\n\"@a\".url = \"u\"\n\"@a\".tag = \"v\"\n"
		+ PG
		+ "[aliases]\n\"@x\" = \"s\"\n",
	)?
	expect_equal(
		remove_dependency(KEYED, "@a")?,
		"[project]\nname = \"a\"\n[aliases]\n\"@x\" = \"s\"\n",
	)?
	expect_equal(remove_dependency(INLINE, "@a")?, "[project]\nname = \"a\"\n")?

test "multi-line values stay whole":
	expect_equal(
		add_dependency(ML, "@pg", URL, Pin.Tag("v1"))?,
		"[project]\nname = \"a\"\nlist = [\n  1,\n  2,\n]\n[dependencies]\n"
		+ "\"@a\" = { url = \"u\", tag = \"v\" }\n"
		+ PG
		+ "[effects]\n\"@a\" = [\n  \"std.net.*\",\n  \"std.fs.read\", # c\n]\n",
	)?
	expect_equal(
		allow_effects(ML, "@a", ["std.x"])?,
		"[project]\nname = \"a\"\nlist = [\n  1,\n  2,\n]\n[dependencies]\n"
		+ "\"@a\" = { url = \"u\", tag = \"v\" }\n[effects]\n\"@a\" = [\"std.x\"]\n",
	)?
	expect_equal(
		allow_effects(ML, "@pg", ["std.x"])?,
		"[project]\nname = \"a\"\nlist = [\n  1,\n  2,\n]\n[dependencies]\n"
		+ "\"@a\" = { url = \"u\", tag = \"v\" }\n[effects]\n\"@a\" = [\n  \"std.net.*\",\n  \"std.fs.read\", # c\n]\n\"@pg\" = [\"std.x\"]\n",
	)?
	expect_equal(
		remove_dependency(ML, "@a")?,
		"[project]\nname = \"a\"\nlist = [\n  1,\n  2,\n]\n",
	)?

	text := "[project]\nname = \"\"\"\na\n[dependencies]\n\"\"\"\n"
	expect_equal(
		add_dependency(text, "@pg", URL, Pin.Tag("v1"))?,
		text + "\n[dependencies]\n" + PG,
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
