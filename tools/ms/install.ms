// `ms install`, `ms add` and `ms remove`. Installing is libms's (`ms_tool_install`,
// compiler/include/ms/tool.h), so a program that imports this module links
// `libmstool.a`.
// `add` and `remove` edit the `[dependencies]` and `[effects]` tables of `ms.toml` with
// manifest_edit.ms, keeping every comment and the layout of the rest of the file.
// Anything the Rust command words differently (a workspace root, a requirement that
// does not parse) goes to the Rust command, before a file is touched.
import (
	working_directory from "@std/os/env.ms",
	exists, read_file, write_file from "@std/os/fs.ms",
	dirname, join from "@std/os/path.ms",
	expect_equal from "@std/test/test.ms",

	Printed from "./fmt.ms",
	Pin,
	add_dependency,
	allow_effects,
	default_name,
	remove_dependency,
	valid_alias from "./manifest_edit.ms",
)

// Status 1 of `ms_tool_install` is an error with the Rust text; status 2 is a project
// the C reader does not cover (a workspace).
export enum InstallError:
	Failed(message: String)
	Unsupported(message: String)

extern fn ms_tool_install(
	manifest: String,
	update: List[String],
	locked: Bool,
	frozen: Bool,
) List[String]!InstallError

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
			if at + 1 >= args.length(): return Printed(
				stderr: "ms install: --update needs a package name such as @pg\n",
				status: 1,
			)

			update.append(args[at + 1].clone())
			at += 1
		else if arg.starts_with("-"):
			return Printed(
				stderr: f"ms install: unknown option {arg}; see ms install --help\n",
				status: 1,
			)
		else:
			manifest = arg

		at += 1

	if manifest.is_empty():
		found := find_project()
		if found.is_none(): return Printed(
			stderr: "ms install: no ms.toml here or above; run `ms init` first\n",
			status: 1,
		)

		manifest = found.get()

	done := install_manifest(manifest, update)
	if done.rust: return none
	if not done.message.is_empty(): return failure("install", done.message)

	return Printed(stdout: fetched_rows(done.rows))

// Whether `text` is a version requirement the Rust parser accepts: one to three numbers
// with an optional `^`, `~` or `=`, and an optional `-` suffix of identifiers.
fn requirement_parses(text: String) Bool:
	var rest = text.clone()
	if rest.starts_with("^") or rest.starts_with("~") or rest.starts_with("="): rest = rest.slice(
		1,
		rest.length(),
	)

	var numbers = rest.clone()

	if at := rest.index_of("-"):
		numbers = rest.slice(0, at)

		suffix := rest.slice(at + 1, rest.length())
		if suffix.is_empty(): return false

		for id in suffix.split("."):
			if id.is_empty(): return false

			for c in id.chars():
				ok := (
					(c >= "a" and c <= "z")
					or (c >= "A" and c <= "Z")
					or (c >= "0" and c <= "9")
					or c == "-"
				)
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
		if not (
			(c >= "0" and c <= "9")
			or (c >= "a" and c <= "f")
			or (c >= "A" and c <= "F")
		): return false
	return true

// How the flag `ms add` was given pins the dependency.
fn pin_of(kind: String, reference: String) Pin:
	if kind == "sha": return Pin.Sha(reference.clone())
	if kind == "version": return Pin.Version(reference.clone())

	return Pin.Tag(reference.clone())

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
		if not needs.is_empty() and at + 1 >= args.length(): return failure(
			"add",
			f"{arg} needs {needs}",
		)

		if arg == "--version" or arg == "--tag" or arg == "--sha":
			if not kind.is_empty(): return failure(
				"add",
				"name exactly one of --version, --tag and --sha",
			)

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

	// A requirement or a name the Rust command words an error for, and a manifest this
	// does not edit, are left to it.
	if kind == "version" and not requirement_parses(reference): return none
	if kind == "sha" and not is_commit(reference): return none
	if not valid_alias(name): return none

	manifest := find_project()
	if manifest.is_none(): return failure(
		"add",
		"no ms.toml here or above; run `ms init` first",
	)

	original := read_text(manifest.get())
	if original.is_none() or original.get().contains("[workspace"): return none

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

	if done.rust or not done.message.is_empty():
		// A dependency that cannot be installed is not left in the manifest.
		void write_file(manifest.get(), original.get(), replace: true).wait()
		if done.rust: return none

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

// Runs `ms remove`; none when the Rust command must.
export fn run_remove(args: List[String]) Printed?:
	if args.length() != 1: return failure("remove", "name one package: ms remove @name")

	name := args[0].clone()
	manifest := find_project()
	if manifest.is_none(): return failure(
		"remove",
		"no ms.toml here or above; run `ms init` first",
	)

	original := read_text(manifest.get())
	if original.is_none() or original.get().contains("[workspace"): return none

	edited := remove_dependency(original.get(), name)
	if edited.is_error(): return failure("remove", edited.err().message)

	written := write_file(manifest.get(), edited.get(), replace: true).wait()
	if written.is_error(): return failure(
		"remove",
		f"write {manifest.get()}: {written.err().message}",
	)

	done := install_manifest(manifest.get(), [])

	if done.rust or not done.message.is_empty():
		void write_file(manifest.get(), original.get(), replace: true).wait()
		if done.rust: return none

		return failure("remove", done.message)

	return Printed(stdout: f"removed {name}\n")

// ---------------------------------------------------------------- tests

test "requirements the Rust parser accepts":
	expect_equal(requirement_parses("1.2"), true)?
	expect_equal(requirement_parses("~1.2.3"), true)?
	expect_equal(requirement_parses("=1.2.3-rc.1"), true)?
	expect_equal(requirement_parses("1.2.3.4"), false)?
	expect_equal(requirement_parses("x"), false)?
