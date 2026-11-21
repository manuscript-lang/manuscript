// `ms install`, `ms add` and `ms remove`. Installing is libms's (`ms_tool_install`,
// src/compiler/include/ms/tool.h), so a program that imports this module links
// `libmstool.a`.
// `add` and `remove` edit the `[dependencies]` and `[effects]` tables of `ms.toml` with
// manifest_edit.ms, keeping every comment and the layout of the rest of the file.
// A dependency that cannot be installed is not left in the manifest.
import (
	Matches from "@std/cli/command.ms",
	working_directory from "@std/os/env.ms",
	exists, read_file, write_file from "@std/os/fs.ms",
	dirname, join from "@std/os/path.ms",
	expect_true from "@std/test/test.ms",

	Printed from "./fmt.ms",
	Pin,
	add_dependency,
	allow_effects,
	default_name,
	remove_dependency from "./manifest_edit.ms",
	find, message_of, root_workspace from "./workspace.ms",
)

// Status 1 of the natives below is an error with the Rust text.
export enum InstallError:
	Failed(message: String)
	Unsupported(message: String)

extern fn ms_tool_install(
	manifest: String,
	update: List[String],
	locked: Bool,
	frozen: Bool,
) List[String]!InstallError

// A workspace's members (`name\tmanifest` rows) resolve into one `ms.lock` at
// `lock_root`.
extern fn ms_tool_install_workspace(
	lock_root: String,
	members: List[String],
	update: List[String],
	locked: Bool,
	frozen: Bool,
) List[String]!InstallError

// The Rust text of why `text` is not a version requirement.
extern fn ms_tool_requirement(text: String) List[String]!InstallError

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

// Whether `manifest` is a workspace root with no `[project]`, which has no dependencies
// of its own to edit.
fn is_root(manifest: String) Bool:
	found := root_workspace(manifest)
	return found.is_ok() and found.get().is_some()

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

fn install_error(error: InstallError) String:
	match error:
		Failed(message): return message.clone()
		Unsupported(message): return message.clone()

fn install_manifest(manifest: String, update: List[String]) Installed:
	// A project of a workspace installs every member into the root's one lock.
	space := find(manifest.clone())
	if space.is_error(): return Installed(message: message_of(space.err()))

	if workspace := space.get():
		var rows = List[String]()
		for member in workspace.members: rows.append(
			f"{member.name}\t{member.manifest}"
		)

		got := ms_tool_install_workspace(
			workspace.root.clone(),
			rows,
			update,
			false,
			false,
		)
		if got.is_error(): return Installed(message: install_error(got.err()))

		return Installed(rows: got.get().clone())

	got := ms_tool_install(manifest, update, false, false)
	if got.is_error(): return Installed(message: install_error(got.err()))

	return Installed(rows: got.get().clone())

// Runs `ms install`.
export fn run_install(m: Matches) Printed:
	update := m.list("update")
	var manifest = m.string_or_none("manifest").get_or("")

	if manifest.is_empty():
		found := find_project()
		if found.is_none(): return Printed(
			stderr: "ms install: no ms.toml here or above; run `ms init` first\n",
			status: 1,
		)

		manifest = found.get()

	done := install_manifest(manifest, update)
	if not done.message.is_empty(): return failure("install", done.message)

	return Printed(stdout: fetched_rows(done.rows))

// How the flag `ms add` was given pins the dependency.
fn pin_of(kind: String, reference: String) Pin:
	if kind == "sha": return Pin.Sha(reference.clone())
	if kind == "version": return Pin.Version(reference.clone())

	return Pin.Tag(reference.clone())

// The text of the manifest, or the failure to print.
fn read_manifest(command: String, path: String) String!Printed:
	data := read_file(path).wait()
	if data.is_error(): return error(
		failure(command, f"read {path}: {data.err().message}")
	)

	text := data.get().decode_utf8()
	if text.is_none(): return error(
		failure(command, f"read {path}: stream did not contain valid UTF-8")
	)

	return ok(text.get())

fn quoted_list(effects: List[String]) String:
	var out = List[String]()
	for effect in effects: out.append(f"\"{effect}\"")
	return out.join(", ")

// Runs `ms add`.
export fn run_add(m: Matches) Printed:
	url := m.string("url")
	var name = m.string_or_none("as").get_or("")
	allow := m.bool("allow")
	var kind = ""
	var reference = ""

	for choice in ["version", "tag", "sha"]:
		if value := m.string_or_none(choice):
			if not kind.is_empty(): return failure(
				"add",
				"name exactly one of --version, --tag and --sha",
			)

			kind = choice.clone()
			reference = value.clone()

	if url.is_empty(): return failure(
		"add",
		"name a repository URL: ms add <url> --version <requirement>",
	)
	if kind.is_empty(): return failure(
		"add",
		"name the version: --version <requirement>, --tag <tag> or --sha <full commit>",
	)

	if name.is_empty():
		made := default_name(url)
		if made.is_none(): return failure(
			"add",
			f"cannot make a package name from {url}; give one with --as @name",
		)

		name = made.get()

	if kind == "version":
		parsed := ms_tool_requirement(reference)
		if parsed.is_error(): return failure("add", install_error(parsed.err()))

	manifest := find_project()
	if manifest.is_none(): return failure(
		"add",
		"no ms.toml here or above; run `ms init` first",
	)
	if is_root(manifest.get()): return failure(
		"add",
		f"{manifest.get()} is a workspace root; run ms add inside a member directory",
	)

	original := read_manifest("add", manifest.get())
	if original.is_error(): return original.err()

	edited := add_dependency(original.get(), name, url, pin_of(kind, reference))
	if edited.is_error(): return failure("add", edited.err().message)

	// `--allow` writes under [effects] after the install; refuse before touching a file when
	// that table cannot take an entry.
	probe := allow_effects(edited.get(), name, ["x"])
	if allow and probe.is_error(): return failure("add", probe.err().message)

	written := write_file(manifest.get(), edited.get(), replace: true).wait()
	if written.is_error(): return failure(
		"add",
		f"write {manifest.get()}: {written.err().message}",
	)

	done := install_manifest(manifest.get(), [])

	if not done.message.is_empty():
		void write_file(manifest.get(), original.get(), replace: true).wait()
		return failure("add", done.message)

	var out = fetched_rows(done.rows)
	var effects = List[String]()

	for row in done.rows:
		parts := row.split("\t")
		if parts.length() >= 5 and parts[0] == name and parts[4] != "none": effects = (
			parts[4]
			.clone()
			.split(" ")
		)

	if effects.is_empty(): return Printed(stdout: out)

	if allow:
		allowed := allow_effects(edited.get(), name, effects)
		if allowed.is_error(): return failure("add", allowed.err().message)

		rewritten := write_file(manifest.get(), allowed.get(), replace: true).wait()
		if rewritten.is_error(): return failure(
			"add",
			f"write {manifest.get()}: {rewritten.err().message}",
		)

		out += f"{name} is allowed {effects.join(" ")}\n"
	else:
		out += f"{name} declares effects. Allow them to build: add to [effects]\n  \"{name}\" = [{quoted_list(effects)}]\nor run `ms add --allow` next time.\n"

	return Printed(stdout: out)

// Runs `ms remove`.
export fn run_remove(m: Matches) Printed:
	name := m.string("name")
	manifest := find_project()
	if manifest.is_none(): return failure(
		"remove",
		"no ms.toml here or above; run `ms init` first",
	)
	if is_root(manifest.get()): return failure(
		"remove",
		f"{manifest.get()} is a workspace root; run ms remove inside a member directory",
	)

	original := read_manifest("remove", manifest.get())
	if original.is_error(): return original.err()

	edited := remove_dependency(original.get(), name)
	if edited.is_error(): return failure("remove", edited.err().message)

	written := write_file(manifest.get(), edited.get(), replace: true).wait()
	if written.is_error(): return failure(
		"remove",
		f"write {manifest.get()}: {written.err().message}",
	)

	done := install_manifest(manifest.get(), [])

	if not done.message.is_empty():
		void write_file(manifest.get(), original.get(), replace: true).wait()
		return failure("remove", done.message)

	return Printed(stdout: f"removed {name}\n")

// ---------------------------------------------------------------- tests

test "requirements the Rust parser accepts":
	expect_true(ms_tool_requirement("1.2").is_ok())?
	expect_true(ms_tool_requirement("~1.2.3").is_ok())?
	expect_true(ms_tool_requirement("=1.2.3-rc.1").is_ok())?
	expect_true(ms_tool_requirement("1.2.3.4").is_error())?
	expect_true(ms_tool_requirement("x").is_error())?
