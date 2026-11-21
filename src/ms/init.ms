// `ms init [--lib | --workspace] [directory]`: create a runnable project or a workspace.
// Exit statuses: 0 created; 1 a file exists or cannot be written; 2 usage error.
import (
	Matches from "@std/cli/command.ms",
	stderr, stdout from "@std/io/io.ms",
	working_directory from "@std/os/env.ms",
	create_directory, read_file, stat, temporary, write_file from "@std/os/fs.ms",
	basename, dirname, join, resolve from "@std/os/path.ms",
	from_scalars from "@std/string.ms",
	expect_equal, expect_true from "@std/test/test.ms",

	errno_text from "./errno.ms",
	quote from "./quote.ms",
)

MAIN := "import arguments from \"@std/os/env.ms\"\n\nfn main() Void:\n\tprint(f\"Arguments: {arguments().length()}\")\n"
TEST := "import expect_equal from \"@std/test/test.ms\"\n\ntest \"arithmetic\":\n\texpect_equal(2 + 3, 5)?\n"
LIB := "export fn greeting(name: String) String: f\"Hello, {name}\"\n"
LIB_TEST := "import (\n\texpect_equal from \"@std/test/test.ms\",\n\n\tgreeting from \"./src/lib.ms\",\n)\n\ntest \"greeting\":\n\texpect_equal(greeting(\"ms\"), \"Hello, ms\")?\n"
WORKSPACE_MAIN := "import greeting from \"@greeter/lib.ms\"\n\nfn main() Void:\n\tprint(greeting(\"ms\"))\n"
IGNORE := ".ms-cache/\n"
// Source, manifests and the lock are LF in every checkout: the formatter writes LF, so
// a Windows checkout that converted them to CRLF would fail `ms fmt --check` on every
// file.
ATTRIBUTES := "*.ms text eol=lf\n*.toml text eol=lf\nms.lock text eol=lf\n"

type File:
	name: String
	content: String

fn say(text: String) Void:
	stdout().write(text + "\n").get()

fn complain(text: String) Void:
	stderr().write(text + "\n").get()

// A manifest name from the directory: lowercase letters, digits, `-` and `_`, falling
// back to `app`.
export fn project_name(directory: String) String:
	var kept = List[Int]()

	for scalar in basename(directory).lower().scalar_values():
		if (
			(scalar >= 97 and scalar <= 122)
			or (scalar >= 48 and scalar <= 57)
			or scalar == 45
			or scalar == 95
		):
			kept.append(scalar)
		else if scalar == 32 or scalar == 46:
			kept.append(45)

	trimmed := from_scalars(kept).get_or("").trim_chars("-_")
	if trimmed.is_empty(): return "app"

	return trimmed

// A path spelled so the argument parser reads it as a file, not an option.
export fn operand(path: String) String:
	if path.starts_with("-"): return f"./{path}"
	return path.clone()

// A path quoted for display in a command the user can paste.
export fn shell_quote(path: String) String:
	if not path.contains_any(" \t\n'\"\\$`!&;|<>()*?[]{}#~"): return path.clone()
	return "'" + path.replace("'", "'\\''") + "'"

fn under(root: String, name: String) String:
	return join([root.clone(), name.clone()])

fn manifest(name: String, source: String, entry: String, extra: String) String:
	return f"[project]\nname = {quote(name)}\nsource = \"{source}\"\n{entry}{extra}"

// The text of the file at `path`, empty when there is none.
fn existing(path: String) String!:
	read := read_file(path).wait()

	if read.is_error():
		if read.err().kind == "ENOENT": return ok("")
		return error(read.err())

	return ok(read.get().decode_utf8().get_or(""))

// Appends `lines` to the file at `path` unless one of its lines satisfies `present`.
fn append_once(path: String, lines: String, present: fn(String) Bool) Void!:
	text := existing(path)?
	for line in text.split("\n"):
		if present(line.trim()): return ok()

	var content = text
	if not content.is_empty() and not content.ends_with("\n"): content += "\n"
	write_file(path, content + lines, replace: true).wait()?

fn ignores_cache(line: String) Bool:
	return [".ms-cache", ".ms-cache/", "/.ms-cache", "/.ms-cache/"].contains(line)

fn pins_source(line: String) Bool:
	return line.starts_with("*.ms ")

fn files_for(absolute: String, library: Bool, workspace: Bool) List[File]:
	if workspace:
		app := manifest(
			"app",
			"./src",
			"entry = \"./src/main.ms\"\n",
			"\n[dependencies]\n\"@greeter\" = { path = \"../libs/greeter\" }\n",
		)
		return [
			File(
				"ms.toml",
				"[workspace]\nmembers = [\"app\", \"libs/*\"]\n",
			),
			File("app/ms.toml", app),
			File("app/src/main.ms", WORKSPACE_MAIN),
			File("app/test.ms", TEST),
			File(
				"libs/greeter/ms.toml",
				manifest("greeter", "./src", "", ""),
			),
			File("libs/greeter/src/lib.ms", LIB),
			File("libs/greeter/test.ms", LIB_TEST),
		]

	name := project_name(absolute)
	if library:
		return [
			File("ms.toml", manifest(name, "./src", "", "")),
			File("src/lib.ms", LIB),
			File("test.ms", LIB_TEST),
		]

	return [
		File(
			"ms.toml",
			manifest(name, "./src", "entry = \"./src/main.ms\"\n", ""),
		),
		File("src/main.ms", MAIN),
		File("test.ms", TEST),
	]

fn create(absolute: String, files: List[File]) Void!:
	for file in files:
		path := under(absolute, file.name)
		create_directory(dirname(path), true)?
		write_file(path, file.content).wait()?

	append_once(under(absolute, ".gitignore"), IGNORE, ignores_cache)?
	append_once(under(absolute, ".gitattributes"), ATTRIBUTES, pins_source)?

// Reads the parsed `ms init` words, then creates the project.
export fn run_init_command(m: Matches) Int:
	library := m.bool("lib")
	workspace := m.bool("workspace")
	directory := m.string_or_none("directory").get_or(".")

	if library and workspace:
		complain(
			"ms init takes --lib or --workspace, not both; e.g. ms init --lib greeter"
		)
		return 2

	if directory.is_empty():
		complain(
			"ms init: the directory is empty; pass a directory name such as ms init hello, or omit it for the current directory"
		)
		return 2

	return run_init(directory, library, workspace)

// Creates a project in `directory`: a library, a workspace, or an application.
export fn run_init(directory: String, library: Bool, workspace: Bool) Int:
	here := working_directory()

	if here.is_error():
		complain(here.err().message)
		return 1

	resolved := resolve(here.get(), [directory.clone()])

	if resolved.is_error():
		complain(resolved.err().message)
		return 1

	absolute := resolved.get()
	files := files_for(absolute, library, workspace)

	for file in files:
		if exists_here(under(absolute, file.name)):
			complain(
				f"ms init: {under(directory, file.name)} already exists; run it in an empty directory or remove the file first"
			)
			return 1

	made := create(absolute, files)

	if made.is_error():
		complain(
			f"ms init: cannot create project in {directory}: {errno_text(made.err())}"
		)
		return 1

	say(f"Created project in {directory}")

	manifest_path := shell_quote(operand(under(directory, "ms.toml")))

	if workspace:
		app := shell_quote(operand(under(directory, "app/ms.toml")))
		say(f"Next: ms run {app}; ms test runs every member from {directory}")
	else if library:
		say(f"Next: ms test {manifest_path}")
	else:
		say(f"Next: ms run {manifest_path} -- first second")

	return 0

// Whether `path` names anything, a dangling symbolic link included.
fn exists_here(path: String) Bool:
	return stat(path, false).is_ok()

test "manifest names keep lowercase letters, digits, dashes and underscores":
	expect_equal(project_name("/x/My App.v2"), "my-app-v2")?
	expect_equal(project_name("/x/___"), "app")?
	expect_equal(project_name("/x/Hello"), "hello")?

test "operands and quoting survive pasting":
	expect_equal(operand("-demo/ms.toml"), "./-demo/ms.toml")?
	expect_equal(operand("demo/ms.toml"), "demo/ms.toml")?
	expect_equal(shell_quote("a b/ms.toml"), "'a b/ms.toml'")?
	expect_equal(shell_quote("hello/ms.toml"), "hello/ms.toml")?
	expect_equal(shell_quote("it's"), "'it'\\''s'")?

test "init creates a project, keeps an existing gitattributes and refuses to overwrite":
	scratch := temporary("ms-init-")?
	root := scratch.path()
	kept := join([root.clone(), "kept"])
	create_directory(kept.clone(), true)?
	write_file(join([kept.clone(), ".gitattributes"]), "*.png binary").wait()?
	expect_equal(run_init(join([root.clone(), "fresh"]), false, false), 0)?
	expect_equal(run_init(kept.clone(), false, false), 0)?
	expect_equal(run_init(kept.clone(), false, false), 1)?

	fresh := read_file(join([root.clone(), "fresh/.gitattributes"])).wait()?
	expect_equal(fresh.decode_utf8().get_or(""), ATTRIBUTES)?

	appended := read_file(join([kept.clone(), ".gitattributes"])).wait()?
	expect_true(
		appended.decode_utf8().get_or("").starts_with(
			"*.png binary\n*.ms text eol=lf\n"
		)
	)?
