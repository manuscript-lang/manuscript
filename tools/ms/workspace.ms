// Workspaces: a root `ms.toml` with `[workspace] members` names directories that each
// hold a project. Members import one another through `{ path = "../util" }`
// dependencies and share the root's `ms.lock`. This is the port of
// crates/ms-driver/src/project/workspace.rs over the one manifest reader (project.ms),
// with the same error texts.
import (
	working_directory from "@std/os/env.ms",
	FileKind,
	canonicalize,
	create_directory,
	list,
	stat,
	temporary,
	write_file from "@std/os/fs.ms",
	basename, dirname, is_absolute, join, relative, resolve from "@std/os/path.ms",
	expect_equal, expect_true from "@std/test/test.ms",

	Project, ProjectError, read_project from "./project.ms",
)

// A project of a workspace.
export type Member:
	// `[project] name`, unique in the workspace.
	name: String
	// The member's `ms.toml`, canonical.
	manifest: String
	// The canonical directory holding it.
	root: String

// A workspace root and its members, the root's own project first when it has one.
export type Workspace:
	// The canonical directory holding the root `ms.toml` and `ms.lock`.
	root: String
	members: List[Member]

fn failed(message: String) ProjectError:
	return ProjectError.Failed(message)

// The text of either kind of error.
export fn message_of(error: ProjectError) String:
	match error:
		Failed(message): return message.clone()
		Unsupported(message): return message.clone()

fn is_directory(path: String) Bool:
	info := stat(path)
	return info.is_ok() and info.get().kind == FileKind.Directory

fn is_file(path: String) Bool:
	info := stat(path)
	return info.is_ok() and info.get().kind == FileKind.File

fn within(root: String, dir: String) Bool:
	return dir == root or dir.starts_with(root + "/") or dir.starts_with(root + "\\")

// Whether `path` climbs out of its start with a `..` part.
fn escapes(path: String) Bool:
	for part in path.replace("\\", "/").split("/"):
		if part == "..": return true
	return false

// `dir` below `root`, or `dir` itself for the root or a path with no relative form.
fn rel_or(root: String, dir: String) String:
	shown := relative(root, dir)
	if shown.is_error() or shown.get() == "." or shown.get().is_empty(): return dir.clone()

	return shown.get().clone()

fn absolute(path: String) String!ProjectError:
	if is_absolute(path): return ok(path.clone())

	here := working_directory()
	if here.is_error(): return error(
		failed(f"cannot read the working directory: {here.err().message}")
	)

	made := resolve(here.get(), [path.clone()])
	if made.is_error(): return error(
		failed(f"cannot resolve {path}: {made.err().message}")
	)

	return ok(made.get().clone())

fn canonical(path: String) String!ProjectError:
	made := canonicalize(path)
	if made.is_error(): return error(failed(f"{path}: {made.err().message}"))

	return ok(made.get().clone())

fn bad_pattern(pattern: String, why: String) ProjectError:
	return failed(
		f"workspace member \"{pattern}\" {why}; write a directory below the workspace root such as \"app\" or \"libs/*\""
	)

// The canonical directories that `pattern` names under `root`.
fn pattern_dirs(root: String, pattern: String) List[String]!ProjectError:
	wildcard := pattern.ends_with("/*")
	base := if wildcard: pattern.slice(0, pattern.length() - 2) else: pattern.clone()
	if base.is_empty() or is_absolute(base) or escapes(base) or base.contains("*"): return error(
		bad_pattern(pattern, "is not a relative directory inside the workspace")
	)

	parent := canonicalize(join([root.clone(), base]))
	if parent.is_error(): return error(bad_pattern(pattern, "does not exist"))
	if not within(root, parent.get()): return error(
		bad_pattern(pattern, "leaves the workspace root")
	)
	if not wildcard: return ok([parent.get().clone()])

	listing := list(parent.get())
	if listing.is_error(): return error(
		failed(f"read directory {parent.get()}: {listing.err().message}")
	)

	var children = List[String]()

	for entry in listing.get():
		// A hidden directory (.git, .cache) is never a member.
		if entry.name.starts_with("."): continue

		path := join([parent.get().clone(), entry.name.clone()])
		if not is_file(join([path.clone(), "ms.toml"])): continue

		found := canonicalize(path)
		if found.is_ok() and within(root, found.get()): children.append(
			found.get().clone()
		)

	return ok(children.sorted())

// Expands and checks the members of the parsed workspace root `root_project`.
export fn read(root_project: Project) Workspace!ProjectError:
	root := root_project.root.clone()
	var dirs = List[String]()

	// The root's own project, when it has one, is a member.
	if not root_project.name.is_empty(): dirs.append(root.clone())
	for pattern in root_project.members:
		dirs.extend(pattern_dirs(root, pattern)?)
	if dirs.is_empty(): return error(
		failed(
			"workspace lists no members; name each member directory under [workspace], such as members = [\"app\", \"libs/*\"]"
		)
	)

	var members = List[Member]()

	for dir in dirs:
		var repeated = false
		for member in members:
			if member.root == dir: repeated = true
		if repeated: continue

		manifest := join([dir.clone(), "ms.toml"])
		project := read_project(manifest.clone())
		if project.is_error(): return error(
			failed(
				f"workspace member {rel_or(root, dir)}: {message_of(project.err())}"
			)
		)
		if dir != root and is_file(join([dir.clone(), "ms.lock"])): return error(
			failed(
				f"workspace member {rel_or(root, dir)} has its own ms.lock, which is never read; the workspace keeps one ms.lock at {root}, so delete the member's"
			)
		)

		name := project.get().name.clone()
		if name.is_empty(): return error(
			failed(
				f"workspace member {rel_or(root, dir)} has no [project]; a member is a project with a name and source"
			)
		)

		for member in members:
			if member.name == name: return error(
				failed(
					f"workspace members {rel_or(root, member.root)} and {rel_or(root, dir)} are both named \"{name}\"; rename one in [project]"
				)
			)
		members.append(Member(name, manifest, dir.clone()))

	return ok(Workspace(root, members))

// The workspace that contains the project whose `ms.toml` is `manifest`: the manifest
// itself when it has `[workspace]`, else the nearest ancestor manifest that lists this
// directory. None for a project outside any workspace; a nearer, unrelated project does
// not make an ancestor workspace its own.
export fn find(manifest: String) Workspace?!ProjectError:
	here := canonical(dirname(absolute(manifest)?))?
	var dir = here.clone()

	while true:
		candidate := join([dir.clone(), "ms.toml"])

		if is_file(candidate):
			// A broken or unrelated ancestor manifest is not a workspace; its own
			// errors surface when it is the project being built.
			project := read_project(candidate)

			if project.is_ok() and project.get().workspace:
				workspace := read(project.get())?
				if dir == here: return ok(workspace)

				for member in workspace.members.clone():
					if member.root == here: return ok(workspace)
				return ok(none)

		parent := dirname(dir)
		if parent == dir: return ok(none)

		dir = parent

	return ok(none)

// The members of `manifest` when it is a workspace root with no `[project]` of its own,
// so a command aimed at it means "every member". None for any other manifest or file.
export fn root_workspace(manifest: String) Workspace?!ProjectError:
	if basename(manifest) != "ms.toml" or not is_file(manifest): return ok(none)

	// A manifest that does not parse is reported by the command itself, in its own
	// format.
	project := read_project(manifest)
	if project.is_error(): return ok(none)
	if not project.get().workspace or not project.get().name.is_empty(): return ok(none)

	return ok(read(project.get())?)

// The members of the workspace root at `manifest`, or none when it is not one or
// something about it needs the Rust command line to explain.
export fn root_members(manifest: String) List[Member]?:
	found := root_workspace(manifest)
	if found.is_error() or found.get().is_none(): return none

	return found.get().get().members.clone()

// ---------------------------------------------------------------- tests

fn write_manifest(directory: String, text: String) Void!:
	create_directory(directory.clone(), true)?
	write_file(join([directory, "ms.toml"]), text, replace: true).wait()?

fn project_text(name: String) String:
	return f"[project]\nname = \"{name}\"\nsource = \"src\"\n"

test "a bare path is not a workspace root":
	expect_equal(root_members("nowhere/ms.toml").is_none(), true)?

test "members expand in order, the wildcard sorted and hidden directories skipped":
	scratch := temporary("ms-workspace-")?
	root := scratch.path()
	write_manifest(root.clone(), "[workspace]\nmembers = [\"app\", \"libs/*\"]\n")?
	write_manifest(join([root.clone(), "app"]), project_text("app"))?
	write_manifest(join([root.clone(), "libs/zeta"]), project_text("zeta"))?
	write_manifest(join([root.clone(), "libs/beta"]), project_text("beta"))?
	write_manifest(join([root.clone(), "libs/.hidden"]), project_text("hidden"))?
	create_directory(join([root.clone(), "app/src"]), true)?
	create_directory(join([root.clone(), "libs/zeta/src"]), true)?
	create_directory(join([root.clone(), "libs/beta/src"]), true)?

	found := root_workspace(join([root.clone(), "ms.toml"])).get().get()
	var names = List[String]()
	for member in found.members: names.append(member.name.clone())
	expect_equal(names.join(","), "app,beta,zeta")?

	// A member's manifest finds the workspace it belongs to; an unrelated one does not.
	beta := join([root.clone(), "libs/beta/ms.toml"])
	expect_equal(find(beta).get().get().members.length(), 3)?

test "member errors read like the Rust command's":
	scratch := temporary("ms-workspace-")?
	root := scratch.path()
	write_manifest(root.clone(), "[workspace]\nmembers = [\"../out\"]\n")?

	manifest := join([root.clone(), "ms.toml"])
	got := root_workspace(manifest.clone())
	expect_true(
		message_of(got.err()).starts_with(
			"workspace member \"../out\" is not a relative directory inside the workspace;"
		)
	)?
	write_manifest(root.clone(), "[workspace]\nmembers = [\"app\"]\n")?

	got2 := root_workspace(manifest.clone())
	expect_true(message_of(got2.err()).contains("\"app\" does not exist;"))?
