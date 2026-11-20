// A workspace root: an `ms.toml` with `[workspace] members` and no `[project]` of its
// own stands for its members. This reads the happy path; anything the Rust command line
// words as an error (a bad pattern, a missing directory, a member without a name, a
// repeated name, a member with its own `ms.lock`) returns `none` so the caller hands
// the command to it.
import (
	TomlValue, parse from "@std/data/toml.ms",
	working_directory from "@std/os/env.ms",
	FileKind, canonicalize, exists, list, read_file, stat from "@std/os/fs.ms",
	basename, dirname, join, resolve from "@std/os/path.ms",
	expect_equal from "@std/test/test.ms",
)

export type Member:
	name: String
	// The member's `ms.toml`, absolute.
	manifest: String

fn table_of(value: TomlValue, key: String) TomlValue?:
	match value:
		TableValue(entries): return entries.get(key)
		_: return none

fn string_item(item: TomlValue) String?:
	match item:
		StringValue(text): return text.clone()
		_: return none

fn strings_of(value: TomlValue) List[String]?:
	match value:
		ArrayValue(items):
			var out = List[String]()

			for item in items:
				text := string_item(item)
				if text.is_none(): return none

				out.append(text.get())

			return out
		_: return none

fn parsed(path: String) TomlValue?:
	data := read_file(path).wait()
	if data.is_error(): return none

	document := parse(data.get().decode_utf8().get_or(""))
	if document.is_error(): return none

	return document.get()

// The `[project] name` of the manifest at `path`; none when it has none.
fn project_name(path: String) String?:
	document := parsed(path)
	if document.is_none(): return none

	project := table_of(document.get(), "project")
	if project.is_none(): return none

	name := table_of(project.get(), "name")
	if name.is_none(): return none

	match name.get():
		StringValue(text):
			if text.is_empty(): return none
			return text.clone()
		_: return none

fn is_directory(path: String) Bool:
	info := stat(path)
	return info.is_ok() and info.get().kind == FileKind.Directory

// The members of the workspace root at `manifest`, or none when it is not a workspace
// root or something about it needs the Rust command line to explain.
export fn root_members(manifest: String) List[Member]?:
	if basename(manifest) != "ms.toml": return none

	document := parsed(manifest)
	if document.is_none(): return none

	workspace := table_of(document.get(), "workspace").clone()
	if workspace.is_none(): return none

	// A root with a project of its own is a project, not a list of members.
	if project_name(manifest.clone()).is_some(): return none

	found := table_of(workspace.get(), "members")
	if found.is_none(): return none

	patterns := strings_of(found.get())
	if patterns.is_none() or patterns.get().is_empty(): return none

	here := working_directory()
	if here.is_error(): return none

	root := canonicalize(
		dirname(
			resolve(here.get(), [manifest.clone()]).get_or(manifest.clone())
		)
	)
	if root.is_error(): return none

	var dirs = List[String]()

	for pattern in patterns.get():
		var base = pattern.clone()
		wildcard := pattern.ends_with("/*")
		if wildcard: base = pattern.slice(0, pattern.length() - 2)
		if (
			base.is_empty()
			or base.contains("*")
			or base.starts_with("/")
			or base.contains("..")
		):
			return none

		parent := canonicalize(join([root.get(), base]))
		if parent.is_error() or not within(root.get(), parent.get()): return none

		if not wildcard:
			dirs.append(parent.get())
			continue

		listing := list(parent.get())
		if listing.is_error(): return none

		var children = List[String]()

		for entry in listing.get():
			if entry.name.starts_with("."): continue

			path := join([parent.get(), entry.name])
			held := exists(join([path.clone(), "ms.toml"]))

			if held.get_or(false) and is_directory(path):
				canonical := canonicalize(path)
				if canonical.is_ok() and within(root.get(), canonical.get()):
					children.append(canonical.get())

		dirs.extend(children.sorted())

	if dirs.is_empty(): return none

	var members = List[Member]()
	var seen = List[String]()

	for dir in dirs:
		if seen.contains(dir): continue

		seen.append(dir.clone())

		path := join([dir.clone(), "ms.toml"])
		name := project_name(path)
		if name.is_none() or exists(join([dir.clone(), "ms.lock"])).get_or(false): return none

		for member in members:
			if member.name == name.get(): return none
		members.append(Member(name.get(), path))

	return members

fn within(root: String, dir: String) Bool:
	return dir == root or dir.starts_with(root + "/") or dir.starts_with(root + "\\")

test "a bare path is not a workspace root":
	expect_equal(root_members("nowhere/ms.toml").is_none(), true)?
