import (
	Closeable from "@std/core.ms",
	change_directory,
	environment,
	set_environment,
	which,
	working_directory from "@std/os/env.ms",
	chmod, create_directory, temporary, write_file from "@std/os/fs.ms",
	join from "@std/os/path.ms",
	Os, os from "@std/os/system.ms",
	expect_equal from "@std/test/test.ms",
)

type SearchEnvironment:
	path: String?
	extensions: String?
	directory: String

impl Closeable for SearchEnvironment:
	var fn close() Unit!:
		try set_environment("PATH", self.path.clone())
		try set_environment("PATHEXT", self.extensions.clone())
		try change_directory(self.directory)

fn saved_variable(values: Map[String, String], name: String) String?:
	windows := os() == Os.Windows

	for entry in values.entries():
		key := if windows: entry.key.upper() else: entry.key
		if key == name: return entry.value.clone()

	return none

fn save_search_environment() SearchEnvironment!:
	values := try environment()
	return ok(
		SearchEnvironment(
			saved_variable(values, "PATH"),
			saved_variable(values, "PATHEXT"),
			try working_directory(),
		)
	)

fn make_program(path: String) Unit!:
	try write_file(path, "#!/bin/sh\nexit 0\n", false).wait()
	try chmod(path, 493)

test "which preserves PATH order and rejects directories and nonexecutable files":
	directory := try temporary("manuscript-which-order-")
	_restore := try save_search_environment()
	windows := os() == Os.Windows
	separator := if windows: ";" else: ":"
	suffix := if windows: ".EXE" else: ""
	root := directory.path()
	blocked := join([root.clone(), "blocked"])
	first := join([root.clone(), "first"])
	second := join([root.clone(), "second"])
	try create_directory(blocked, false)
	try create_directory(first, false)
	try create_directory(second, false)
	try create_directory(join([blocked.clone(), "probe{suffix}"]), false)

	expected := join([first.clone(), "probe{suffix}"])
	try make_program(expected)
	try make_program(join([second.clone(), "probe{suffix}"]))
	try set_environment(
		"PATH",
		"{separator}{blocked}{separator}{first}{separator}{second}{separator}",
	)
	try set_environment("PATHEXT", ".EXE;.CMD")
	try expect_equal(which("probe"), expected)
	try expect_equal(which("missing-manuscript-program"), none)
	try expect_equal(which(""), none)

	mode_path := join([first, "mode{suffix}"])
	try write_file(mode_path, "fixture", false).wait()
	try chmod(mode_path, 384)
	try expect_equal(which("mode").is_some(), windows)
	try chmod(mode_path, 493)
	try expect_equal(which("mode"), mode_path)

test "which accepts suffixed names and explicit paths without searching PATH":
	directory := try temporary("manuscript-which-path-")
	_restore := try save_search_environment()
	windows := os() == Os.Windows
	name := if windows: "program.EXE" else: "program.bin"
	path := join([directory.path(), name.clone()])
	try make_program(path)
	try set_environment("PATH", directory.path())
	try set_environment("PATHEXT", ".EXE;.CMD")
	try expect_equal(which(name), path)
	try set_environment("PATH", "")

	forward := path.replace("\\", "/")
	native := if windows: path.replace("/", "\\") else: path.clone()
	try expect_equal(which(forward), forward)
	try expect_equal(which(native), native)

	missing := join([directory.path(), "missing.EXE"])
	try expect_equal(which(missing), none)

test "which honors PATHEXT defaults and skips empty PATH entries":
	directory := try temporary("manuscript-which-extensions-")
	_restore := try save_search_environment()
	windows := os() == Os.Windows
	root := directory.path()
	path_key := if windows: "pAtH" else: "PATH"
	extension_key := if windows: "pAtHeXt" else: "PATHEXT"
	selected_suffix := if windows: ".RUN" else: ""
	selected := join([root.clone(), "selected{selected_suffix}"])
	try make_program(selected)
	try make_program(join([root.clone(), "selected.CMD"]))
	try make_program(join([root.clone(), "ignored.EXE"]))
	try set_environment(path_key, root)
	try set_environment(extension_key, ".RUN;.CMD")
	try expect_equal(which("selected"), selected)
	try expect_equal(which(join([root.clone(), "selected"])), selected)
	try expect_equal(which("ignored"), none)

	default_suffix := if windows: ".CMD" else: ""
	default_path := join([root.clone(), "default{default_suffix}"])
	try make_program(default_path)
	try set_environment(extension_key, none)
	try expect_equal(which("default"), default_path)
	try change_directory(root)
	try set_environment(path_key, "")
	try expect_equal(which("default"), none)

	relative := if windows: ".\\default.CMD" else: "./default"
	try expect_equal(which(relative), relative)
