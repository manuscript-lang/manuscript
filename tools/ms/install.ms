// `ms install`, `ms add` and `ms remove`. Installing is libms's (`ms_tool_install`,
// compiler/include/ms/tool.h), so a program that imports this module links `libmstool.a`.
// `add` and `remove` edit the `[dependencies]` and `[effects]` tables of `ms.toml` as text,
// keeping every comment and the layout of the rest of the file. Anything these cannot edit
// the way the Rust command does (a workspace root, a table written another way, a
// requirement that does not parse) goes to the Rust command, before a file is touched.
import (
	working_directory from "@std/os/env.ms",
	exists, read_file, write_file from "@std/os/fs.ms",
	dirname, join from "@std/os/path.ms",
	expect_equal from "@std/test/test.ms",

	Printed from "./fmt.ms",
)

// Status 1 of `ms_tool_install` is an error with the Rust text; status 2 is a project the C
// reader does not cover (a workspace).
export enum InstallError:
	Failed(message: String)
	Unsupported(message: String)

extern fn ms_tool_install(manifest: String, update: List[String], locked: Bool, frozen: Bool) List[String]!InstallError

// What an edit of the manifest text came to: the new text, or the message of the error the
// Rust command gives.
export type Edited:
	text: String = ""
	message: String = ""

// ---------------------------------------------------------------- text editing

fn is_key_line(line: String) Bool:
	trimmed := line.trim()
	return not trimmed.is_empty() and not trimmed.starts_with("#") and not trimmed.starts_with("[")

// Whether `line` is a header that is `name`'s own table, written plainly.
fn is_header(line: String, name: String) Bool:
	return line.trim() == f"[{name}]" and line.starts_with("[")

// Whether the text names `name` in a way this editor does not handle: a dotted table, an
// inline table or a header with a comment after it.
fn written_otherwise(lines: List[String], name: String) Bool:
	for line in lines:
		trimmed := line.trim()
		if trimmed.starts_with(f"[{name}.") or trimmed.starts_with(f"[[{name}"): return true
		if trimmed.starts_with(f"{name} ") or trimmed.starts_with(f"{name}=") or trimmed.starts_with(f"{name}."): return true
		if trimmed.starts_with(f"[{name}]") and not is_header(line, name): return true

	return false

// A table the editor can reason about: where its header is, and where its lines end.
type Section:
	header: Int
	// The line after the last line of the table.
	end: Int
	// The last line that holds a key, or the header when there is none.
	last_key: Int

// The table `name` of `lines`: none when it is absent; `declined` is set when it is there but
// not plain enough (a key whose value runs over several lines, a repeated header).
type Found:
	section: Section? = none
	declined: Bool = false

fn single_line(line: String) Bool:
	if not line.contains("="): return false
	return line.count("[") == line.count("]") and line.count("{") == line.count("}") and not line.contains("\"\"\"") and not line.contains("'''")

fn find_section(lines: List[String], name: String) Found:
	var found = Found()
	if written_otherwise(lines, name):
		found.declined = true
		return found

	var header = -1

	for i in 0..lines.length():
		if is_header(lines[i], name):
			if header >= 0:
				found.declined = true
				return found

			header = i

	if header < 0: return found

	var end = lines.length()
	var last_key = header

	for i in (header + 1)..lines.length():
		trimmed := lines[i].trim()

		if trimmed.starts_with("["):
			end = i
			break

		if is_key_line(lines[i]):
			if not single_line(lines[i]):
				found.declined = true
				return found

			last_key = i

	found.section = Section(header, end, last_key)
	return found

// The key a line `"@pg" = ...` sets, without quotes.
fn key_of(line: String) String:
	at := line.index_of("=")
	if at.is_none(): return ""

	key := line.slice(0, at.get()).trim()
	if key.length() >= 2 and key.starts_with("\"") and key.ends_with("\""): return key.slice(1, key.length() - 1)

	return key

fn plain(text: String) Bool:
	for c in text.chars():
		if c == "\"" or c == "\\" or c == "\n" or c == "\r" or c == "\t": return false

	return true

fn join_lines(lines: List[String], crlf: Bool) String:
	text := lines.join("\n")
	if crlf: return text.replace("\n", "\r\n")

	return text

// `lines` with `entry` as a key of the table `name`: after its last key, or in a new table
// at the end of the file. none when the table is written some other way.
fn insert_entry(lines: List[String], name: String, key: String, entry: String) Lines?:
	found := find_section(lines, name)
	if found.declined: return none

	if section := found.section:
		for at in (section.header + 1)..section.end:
			if is_key_line(lines[at]) and key_of(lines[at]) == key: return Lines(items: [], message: "exists")

		var out = List[String]()

		for at in 0..lines.length():
			out.append(lines[at].clone())
			if at == section.last_key: out.append(entry.clone())

		return Lines(items: out)

	// A new table at the end, after one blank line.
	var out = List[String]()
	for line in lines: out.append(line.clone())

	if out.length() > 0 and out[out.length() - 1].is_empty(): out.remove(out.length() - 1)
	if out.length() > 0 and out[out.length() - 1].is_empty(): return none

	out.append("")
	out.append(f"[{name}]")
	out.append(entry.clone())
	out.append("")
	return Lines(items: out)

type Lines:
	items: List[String]
	// Set when the key is already there.
	message: String = ""

fn split_text(text: String) List[String]:
	return text.replace("\r\n", "\n").split("\n")

// `text` with `name = { url = ..., tag | sha | version = ... }` under `[dependencies]`.
export fn add_dependency(text: String, name: String, url: String, kind: String, reference: String) Edited?:
	if text.trim().is_empty() or not plain(url) or not plain(reference) or not plain(name): return none

	crlf := text.contains("\r\n")
	entry := f"\"{name}\" = \{ url = \"{url}\", {kind} = \"{reference}\" \}"
	lines := insert_entry(split_text(text), "dependencies", name, entry)
	if lines.is_none(): return none

	if not lines.get().message.is_empty(): return Edited(
		message: f"{name} is already in [dependencies]; run `ms remove {name}` first, or edit its entry",
	)

	return Edited(text: join_lines(lines.get().items, crlf))

// `text` allowing `name` the `effects` it declares, under `[effects]`.
export fn allow_effects(text: String, name: String, effects: List[String]) Edited?:
	if text.trim().is_empty() or not plain(name): return none

	var quoted = List[String]()

	for effect in effects:
		if not plain(effect): return none

		quoted.append(f"\"{effect}\"")

	crlf := text.contains("\r\n")
	entry := f"\"{name}\" = [{quoted.join(", ")}]"
	lines := insert_entry(split_text(text), "effects", name, entry)
	if lines.is_none() or not lines.get().message.is_empty(): return none

	return Edited(text: join_lines(lines.get().items, crlf))

// Removes the key `key` from the table `name`; the table goes with it when nothing is left.
// none when the layout is not one this handles.
fn remove_key(lines: List[String], name: String, key: String) Lines?:
	found := find_section(lines, name)
	if found.declined: return none
	if found.section.is_none(): return Lines(items: [], message: "absent")

	section := found.section.get()
	var at = -1
	var keys = 0

	for i in (section.header + 1)..section.end:
		if not is_key_line(lines[i]): continue

		keys += 1
		if key_of(lines[i]) == key: at = i

	if at < 0: return Lines(items: [], message: "absent")

	// A comment above a key belongs to it, which this does not weigh.
	if at > section.header + 1 and lines[at - 1].trim().starts_with("#"): return none

	var drop_from = at
	var drop_to = at + 1

	if keys == 1:
		// The table goes, with the blank lines and comments in front of its header.
		drop_from = section.header
		while drop_from > 0 and (lines[drop_from - 1].trim().is_empty() or lines[drop_from - 1].trim().starts_with("#")): drop_from -= 1

		drop_to = section.last_key + 1

		// What follows the last key up to the next table stays with that table.
		if drop_from == 0 and drop_to >= lines.length(): return none

	var out = List[String]()

	for i in 0..lines.length():
		if i < drop_from or i >= drop_to: out.append(lines[i].clone())

	return Lines(items: out)

// `text` without `name` in `[dependencies]` and `[effects]`.
export fn remove_dependency(text: String, name: String) Edited?:
	if not plain(name): return none

	crlf := text.contains("\r\n")
	lines := split_text(text)
	removed := remove_key(lines, "dependencies", name)
	if removed.is_none(): return none

	if not removed.get().message.is_empty(): return Edited(message: f"{name} is not in [dependencies]")

	var current = removed.get().items.clone()
	allowed := find_section(current, "effects")
	if allowed.declined: return none

	if allowed.section.is_some():
		again := remove_key(current, "effects", name)
		if again.is_none(): return none

		if again.get().message.is_empty(): current = again.get().items.clone()

	return Edited(text: join_lines(current, crlf))

// ---------------------------------------------------------------- the commands

fn failure(command: String, message: String) Printed:
	return Printed(stderr: f"ms {command}: {message}\n", status: 1)

// The nearest `ms.toml` from the working directory.
fn find_project() String?:
	here := working_directory()
	if here.is_error(): return none

	var directory = here.get().clone()

	while true:
		candidate := join([directory.clone(), "ms.toml"])

		if exists(candidate).get_or(false): return candidate

		parent := dirname(directory)
		if parent == directory: return none

		directory = parent

	return none

fn fetched_rows(rows: List[String]) String:
	var out = ""

	for row in rows:
		parts := row.split("\t")
		if parts.length() < 5: continue

		revision := parts[2]
		short := if revision.length() > 12: revision.slice(0, 12) else: revision.clone()
		out += f"{parts[0]} {parts[1]} {short} (effects: {parts[4]})\n"

	return out

// What installing came to: the rows it printed, or why not.
type Installed:
	rows: List[String] = []
	message: String = ""
	// The C reader does not cover the project.
	rust: Bool = false

fn install_manifest(manifest: String, update: List[String]) Installed:
	got := ms_tool_install(manifest, update, false, false)

	if got.is_error():
		match got.err():
			Failed(message): return Installed(message: message.clone())
			Unsupported(message): return Installed(message: message.clone(), rust: true)

	return Installed(rows: got.get().clone())

// Runs `ms install`; none when the Rust command must.
export fn run_install(args: List[String]) Printed?:
	var update = List[String]()
	var manifest = ""
	var at = 0

	while at < args.length():
		arg := args[at].clone()

		if arg == "--update":
			if at + 1 >= args.length(): return Printed(stderr: "ms install: --update needs a package name such as @pg\n", status: 1)

			update.append(args[at + 1].clone())
			at += 1
		else if arg.starts_with("-"):
			return Printed(stderr: f"ms install: unknown option {arg}; see ms install --help\n", status: 1)
		else:
			manifest = arg

		at += 1

	if manifest.is_empty():
		found := find_project()
		if found.is_none(): return Printed(stderr: "ms install: no ms.toml here or above; run `ms init` first\n", status: 1)

		manifest = found.get()

	done := install_manifest(manifest, update)
	if done.rust: return none
	if not done.message.is_empty(): return failure("install", done.message)

	return Printed(stdout: fetched_rows(done.rows))

// The package name `ms add` gives a repository URL: its last path segment without `.git` and
// without a leading `ms-`, so `https://github.com/acme/ms-pg.git` is `@pg`.
export fn default_name(url: String) String?:
	var trimmed = url.clone()
	while trimmed.ends_with("/"): trimmed = trimmed.slice(0, trimmed.length() - 1)

	var last = trimmed.clone()

	for separator in ["/", ":"]:
		if at := last.last_index_of(separator): last = last.slice(at + 1, last.length())

	if last.ends_with(".git"): last = last.slice(0, last.length() - 4)
	if last.starts_with("ms-"): last = last.slice(3, last.length())

	name := "@" + last.replace("-", "_")
	if not valid_alias(name): return none

	return name

export fn valid_alias(key: String) Bool:
	if not key.starts_with("@") or key.length() < 2: return false

	var first = true

	for c in key.slice(1, key.length()).chars():
		letter := (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or c == "_"
		digit := c >= "0" and c <= "9"
		if not (letter or (digit and not first)): return false

		first = false

	return true

// Whether `text` is a version requirement the Rust parser accepts: one to three numbers with an
// optional `^`, `~` or `=`, and an optional `-` suffix of identifiers.
fn requirement_parses(text: String) Bool:
	var rest = text.clone()
	if rest.starts_with("^") or rest.starts_with("~") or rest.starts_with("="): rest = rest.slice(1, rest.length())

	var numbers = rest.clone()

	if at := rest.index_of("-"):
		numbers = rest.slice(0, at)
		suffix := rest.slice(at + 1, rest.length())
		if suffix.is_empty(): return false

		for id in suffix.split("."):
			if id.is_empty(): return false

			for c in id.chars():
				ok := (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or (c >= "0" and c <= "9") or c == "-"
				if not ok: return false

	parts := numbers.split(".")
	if parts.is_empty() or parts.length() > 3: return false

	for part in parts:
		if part.is_empty(): return false

		for c in part.chars():
			if c < "0" or c > "9": return false

	return true

fn is_commit(text: String) Bool:
	if text.length() != 40: return false

	for c in text.chars():
		if not ((c >= "0" and c <= "9") or (c >= "a" and c <= "f") or (c >= "A" and c <= "F")): return false

	return true

fn read_text(path: String) String?:
	data := read_file(path).wait()
	if data.is_error(): return none

	return data.get().decode_utf8()

fn quoted_list(effects: List[String]) String:
	var out = List[String]()
	for effect in effects: out.append(f"\"{effect}\"")

	return out.join(", ")

// Runs `ms add`; none when the Rust command must.
export fn run_add(args: List[String]) Printed?:
	var url = ""
	var kind = ""
	var reference = ""
	var name = ""
	var allow = false
	var at = 0

	while at < args.length():
		arg := args[at].clone()
		var needs = ""
		if arg == "--version": needs = "a requirement such as 1.2"
		if arg == "--tag": needs = "a tag"
		if arg == "--sha": needs = "a full commit"
		if arg == "--as": needs = "a package name such as @pg"

		if not needs.is_empty() and at + 1 >= args.length(): return failure("add", f"{arg} needs {needs}")

		if arg == "--version" or arg == "--tag" or arg == "--sha":
			if not kind.is_empty(): return failure("add", "name exactly one of --version, --tag and --sha")

			kind = arg.slice(2, arg.length())
			reference = args[at + 1].clone()
			at += 1
		else if arg == "--as":
			name = args[at + 1].clone()
			at += 1
		else if arg == "--allow":
			allow = true
		else if arg.starts_with("-"):
			return failure("add", f"unknown option {arg}; see ms add --help")
		else if url.is_empty():
			url = arg
		else:
			return failure("add", "one repository URL at a time")

		at += 1

	if url.is_empty(): return failure("add", "name a repository URL: ms add <url> --version <requirement>")
	if kind.is_empty(): return failure("add", "name the version: --version <requirement>, --tag <tag> or --sha <full commit>")

	if name.is_empty():
		made := default_name(url)
		if made.is_none(): return failure("add", f"cannot make a package name from {url}; give one with --as @name")

		name = made.get()

	// A requirement or a name the Rust command words an error for, and a manifest this does
	// not edit, are left to it.
	if kind == "version" and not requirement_parses(reference): return none
	if kind == "sha" and not is_commit(reference): return none
	if not valid_alias(name): return none

	manifest := find_project()
	if manifest.is_none(): return failure("add", "no ms.toml here or above; run `ms init` first")

	original := read_text(manifest.get())
	if original.is_none() or original.get().contains("[workspace"): return none

	edited := add_dependency(original.get(), name, url, kind, reference)
	if edited.is_none(): return none

	if not edited.get().message.is_empty(): return failure("add", edited.get().message)

	// `--allow` writes under [effects] after the install; refuse before touching a file when
	// that table is not one this edits.
	if allow and allow_effects(edited.get().text, name, ["x"]).is_none(): return none

	written := write_file(manifest.get(), edited.get().text, replace: true).wait()
	if written.is_error(): return failure("add", f"write {manifest.get()}: {written.err().message}")

	done := install_manifest(manifest.get(), [])

	if done.rust or not done.message.is_empty():
		// A dependency that cannot be installed is not left in the manifest.
		void write_file(manifest.get(), original.get(), replace: true).wait()
		if done.rust: return none

		return failure("add", done.message)

	var out = fetched_rows(done.rows)
	var effects = List[String]()

	for row in done.rows:
		parts := row.split("\t")

		if parts.length() >= 5 and parts[0] == name and parts[4] != "none": effects = parts[4].clone().split(" ")

	if effects.is_empty(): return Printed(stdout: out)

	if allow:
		allowed := allow_effects(edited.get().text, name, effects)
		if allowed.is_none(): return Printed(stdout: out)

		rewritten := write_file(manifest.get(), allowed.get().text, replace: true).wait()
		if rewritten.is_error(): return failure("add", f"write {manifest.get()}: {rewritten.err().message}")

		out += f"{name} is allowed {effects.join(" ")}\n"
	else:
		out += f"{name} declares effects. Allow them to build: add to [effects]\n  \"{name}\" = [{quoted_list(effects)}]\nor run `ms add --allow` next time.\n"

	return Printed(stdout: out)

// Runs `ms remove`; none when the Rust command must.
export fn run_remove(args: List[String]) Printed?:
	if args.length() != 1: return failure("remove", "name one package: ms remove @name")

	name := args[0].clone()
	manifest := find_project()
	if manifest.is_none(): return failure("remove", "no ms.toml here or above; run `ms init` first")

	original := read_text(manifest.get())
	if original.is_none() or original.get().contains("[workspace"): return none

	edited := remove_dependency(original.get(), name)
	if edited.is_none(): return none

	if not edited.get().message.is_empty(): return failure("remove", edited.get().message)

	written := write_file(manifest.get(), edited.get().text, replace: true).wait()
	if written.is_error(): return failure("remove", f"write {manifest.get()}: {written.err().message}")

	done := install_manifest(manifest.get(), [])

	if done.rust or not done.message.is_empty():
		void write_file(manifest.get(), original.get(), replace: true).wait()
		if done.rust: return none

		return failure("remove", done.message)

	return Printed(stdout: f"removed {name}\n")

// ---------------------------------------------------------------- tests

fn base() String:
	return "# my app\n[project]\nname = \"app\" # the name\n"

fn entry(text: String) String:
	return add_dependency(text, "@pg", "https://h/ms-pg.git", "tag", "v1").get().text

test "a dependency goes in a new table at the end":
	expect_equal(
		entry(base()),
		"# my app\n[project]\nname = \"app\" # the name\n\n[dependencies]\n\"@pg\" = { url = \"https://h/ms-pg.git\", tag = \"v1\" }\n",
	)?
	expect_equal(
		entry("[project]\nname = \"app\""),
		"[project]\nname = \"app\"\n\n[dependencies]\n\"@pg\" = { url = \"https://h/ms-pg.git\", tag = \"v1\" }\n",
	)?

test "a dependency goes after the last key of the table":
	text := "[project]\nname = \"app\"\n\n[dependencies]\n# c\n\"@a\" = { url = \"u\", tag = \"t\" }\n\n# about effects\n[effects]\n\"@a\" = []\n"
	expect_equal(
		entry(text),
		"[project]\nname = \"app\"\n\n[dependencies]\n# c\n\"@a\" = { url = \"u\", tag = \"t\" }\n\"@pg\" = { url = \"https://h/ms-pg.git\", tag = \"v1\" }\n\n# about effects\n[effects]\n\"@a\" = []\n",
	)?
	expect_equal(
		entry("[project]\nname = \"app\"\n\n[dependencies]\n"),
		"[project]\nname = \"app\"\n\n[dependencies]\n\"@pg\" = { url = \"https://h/ms-pg.git\", tag = \"v1\" }\n",
	)?

test "a repeated dependency is an error":
	again := add_dependency(entry(base()), "@pg", "https://h/x.git", "tag", "v2")
	expect_equal(again.get().message, "@pg is already in [dependencies]; run `ms remove @pg` first, or edit its entry")?

test "effects are allowed under their own table":
	added := entry("[project]\nname = \"a\"\n")
	expect_equal(
		allow_effects(added, "@pg", ["std.net.*", "x"]).get().text,
		added + "\n[effects]\n\"@pg\" = [\"std.net.*\", \"x\"]\n",
	)?

test "removing leaves the file as it was":
	allowed := allow_effects(entry(base()), "@pg", ["std.net.*"]).get().text
	expect_equal(remove_dependency(allowed, "@pg").get().text.trim_end(), base().trim_end())?
	expect_equal(remove_dependency(base(), "@pg").get().message, "@pg is not in [dependencies]")?

test "removing one of two keeps the table":
	text := "[project]\nname = \"a\"\n\n[dependencies]\n\"@a\" = { url = \"u\", tag = \"t\" }\n\"@b\" = { url = \"u\", tag = \"t\" }\n\n[effects]\n\"@a\" = [\"x\"]\n\"@b\" = [\"y\"]\n"
	expect_equal(
		remove_dependency(text, "@a").get().text,
		"[project]\nname = \"a\"\n\n[dependencies]\n\"@b\" = { url = \"u\", tag = \"t\" }\n\n[effects]\n\"@b\" = [\"y\"]\n",
	)?

test "a manifest with carriage returns keeps them":
	crlf := base().replace("\n", "\r\n")
	added := entry(crlf)
	expect_equal(added.replace("\r\n", "").contains("\n"), false)?
	expect_equal(remove_dependency(added, "@pg").get().text.trim_end(), crlf.trim_end())?

test "names come from the repository":
	expect_equal(default_name("https://github.com/acme/ms-pg.git").get(), "@pg")?
	expect_equal(default_name("https://github.com/acme/wire/").get(), "@wire")?
	expect_equal(default_name("https://github.com/acme/my-lib.git").get(), "@my_lib")?
	expect_equal(default_name("https://github.com/acme/2fast.git").is_none(), true)?

test "requirements the Rust parser accepts":
	expect_equal(requirement_parses("1.2"), true)?
	expect_equal(requirement_parses("~1.2.3"), true)?
	expect_equal(requirement_parses("=1.2.3-rc.1"), true)?
	expect_equal(requirement_parses("1.2.3.4"), false)?
	expect_equal(requirement_parses("x"), false)?
