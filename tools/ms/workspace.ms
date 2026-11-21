// Workspaces: a root `ms.toml` with `[workspace] members` names directories that each
// hold a project. Members import one another through `{ path = "../util" }`
// dependencies and share the root's `ms.lock`. libms reads them (`ms_tool_workspace`,
// compiler/include/ms/tool.h; the compiler needs the same members for path
// dependencies), so a program that imports this module links `libmstool.a`.
import (
	create_directory, temporary, write_file from "@std/os/fs.ms",
	join from "@std/os/path.ms",
	expect_equal, expect_true from "@std/test/test.ms",

	ProjectError from "./project.ms",
)

// A project of a workspace.
export type Member:
	// `[project] name`, unique in the workspace.
	name: String
	// The member's `ms.toml`.
	manifest: String
	// The canonical directory holding it.
	root: String

// A workspace root and its members, the root's own project first when it has one.
export type Workspace:
	// The canonical directory holding the root `ms.toml` and `ms.lock`.
	root: String
	members: List[Member]

extern fn ms_tool_workspace(manifest: String, root_only: Bool) List[String]!ProjectError

// The text of either kind of error.
export fn message_of(error: ProjectError) String:
	match error:
		Failed(message): return message.clone()
		Unsupported(message): return message.clone()

fn from_rows(rows: List[String]) Workspace?:
	var root = ""
	var members = List[Member]()

	for row in rows:
		fields := row.split("\t")

		if fields[0] == "root": root = fields[1].clone()
		else if fields[0] == "member": members.append(
			Member(
				fields[1].clone(),
				join([fields[2].clone(), "ms.toml"]),
				fields[2].clone(),
			)
		)

	if root.is_empty(): return none

	return Workspace(root, members)

// The workspace that contains the project whose `ms.toml` is `manifest`: the manifest
// itself when it has `[workspace]`, else the nearest ancestor manifest that lists this
// directory. None for a project outside any workspace.
export fn find(manifest: String) Workspace?!ProjectError:
	return ok(from_rows(ms_tool_workspace(manifest, false)?))

// The members of `manifest` when it is a workspace root with no `[project]` of its own,
// so a command aimed at it means "every member". None for any other manifest or file.
export fn root_workspace(manifest: String) Workspace?!ProjectError:
	return ok(from_rows(ms_tool_workspace(manifest, true)?))

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
