// The project an `ms.toml` describes, read by libms (`ms_tool_project`,
// src/compiler/include/ms/tool.h): the one manifest reader, so a program that imports
// this module links `libmstool.a`. A manifest the C reader does not cover is
// `Unsupported`; the caller hands the command to the Rust `ms`.
import (
	create_directory, temporary, write_file from "@std/os/fs.ms",
	join from "@std/os/path.ms",
	expect_equal, expect_true from "@std/test/test.ms",
)

// Status 1 of `ms_tool_project` is an error with the Rust text; status 2 is a manifest
// form the C reader does not cover.
export enum ProjectError:
	Failed(message: String)
	Unsupported(message: String)

extern fn ms_tool_project(manifest: String) List[String]!ProjectError

// One `[dependencies]` entry that names a repository.
export type Dependency:
	alias: String
	url: String
	// `tag`, `sha` or `version`.
	kind: String
	// The tag, the commit or the requirement, as written.
	reference: String

// An `ms.toml`, every path canonical and every table in the order the C reader sorted
// it.
export type Project:
	// The canonical directory holding the manifest.
	root: String
	// The base name of the manifest.
	file: String
	// `[project] name`; empty for a workspace root that is not a project.
	name: String
	source: String
	// The entry file, canonical; empty for a library.
	entry: String
	// `[aliases]`: name to canonical path.
	aliases: Map[String, String]
	// `[embed]`: name to canonical directory.
	embed: Map[String, String]
	// `[dependencies]` written `{ path = "../member" }`: name to canonical directory.
	paths: Map[String, String]
	dependencies: List[Dependency]
	// `[effects]`: the patterns each dependency may declare.
	allowed: Map[String, List[String]]
	// `[project] effects`.
	effects: List[String]
	// Whether a `[workspace]` table is present, and its members as written.
	workspace: Bool
	members: List[String]
	// `[project] version`, or empty.
	version: String = ""

fn rows_to_project(rows: List[String]) Project:
	var project = Project(
		root: "",
		file: "",
		name: "",
		source: "",
		entry: "",
		aliases: Map[String, String](),
		embed: Map[String, String](),
		paths: Map[String, String](),
		dependencies: [],
		allowed: Map[String, List[String]](),
		effects: [],
		workspace: false,
		members: [],
		version: "",
	)

	for row in rows:
		fields := row.split("\t")
		kind := fields[0].clone()
		first := fields.get_or(1, "")

		if kind == "root": project.root = first
		else if kind == "file": project.file = first
		else if kind == "name": project.name = first
		else if kind == "source": project.source = first
		else if kind == "entry": project.entry = first
		else if kind == "version": project.version = first
		else if kind == "alias": project.aliases.add(first, fields.get_or(2, ""))
		else if kind == "embed": project.embed.add(first, fields.get_or(2, ""))
		else if kind == "path": project.paths.add(first, fields.get_or(2, ""))
		else if kind == "dep": project.dependencies.append(
			Dependency(
				alias: first,
				url: fields.get_or(2, ""),
				kind: fields.get_or(3, ""),
				reference: fields.get_or(4, ""),
			)
		)
		else if kind == "allow": project.allowed.add(
			first,
			fields.slice(2, fields.length()).get_or([]),
		)
		else if kind == "effect": project.effects.append(first)
		else if kind == "workspace": project.workspace = true
		else if kind == "member": project.members.append(first)

	return project

// Reads the manifest at `manifest`.
export fn read_project(manifest: String) Project!ProjectError:
	rows := ms_tool_project(manifest)?
	return ok(rows_to_project(rows))

test "a manifest reads into a project":
	scratch := temporary("ms-project-")?
	root := scratch.path()
	create_directory(join([root.clone(), "src"]), true)?
	write_file(join([root.clone(), "src/main.ms"]), "fn main() Int:\n\treturn 0\n").wait()?

	text := "[project]\nname = \"demo\"\nsource = \"src\"\nentry = \"src/main.ms\"\nversion = \"1.2.3\"\n[dependencies]\n\"@pg\" = { url = \"https://example.com/pg\", tag = \"v1\" }\n"
	manifest := join([root.clone(), "ms.toml"])
	write_file(manifest.clone(), text).wait()?

	got := read_project(manifest)

	if got.is_error():
		match got.err():
			Failed(message): expect_equal(message.clone(), "")?
			Unsupported(message): expect_equal(message.clone(), "")?

	project := got.get()
	expect_equal(project.name, "demo")?
	expect_true(project.entry.ends_with("/src/main.ms"))?
	expect_equal(project.version, "1.2.3")?
	expect_equal(project.dependencies.length(), 1)?
	expect_equal(project.dependencies[0].alias, "@pg")?
	expect_equal(project.dependencies[0].kind, "tag")?
	expect_equal(project.dependencies[0].reference, "v1")?
