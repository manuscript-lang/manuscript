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
		set_environment("PATH", self.path.clone())?
		set_environment("PATHEXT", self.extensions.clone())?
		change_directory(self.directory)?

fn saved_variable(values: Map[String, String], name: String) String?:
	windows := os() == Os.Windows

	for entry in values.entries():
		key := if windows: entry.key.upper() else: entry.key
		if key == name: return entry.value.clone()

	return none

fn save_search_environment() SearchEnvironment!:
	values := environment()?
	return ok(
		SearchEnvironment(
			saved_variable(values, "PATH"), saved_variable(values, "PATHEXT"),
			working_directory()?
		)
	)

fn make_program(path: String) Unit!:
	write_file(path, "#!/bin/sh\nexit 0\n", false).wait()?
	chmod(path, 493)?

test "which preserves PATH order and rejects directories and nonexecutable files":
	directory := temporary("manuscript-which-order-")?
	_restore := save_search_environment()?
	windows := os() == Os.Windows
	separator := if windows: ";" else: ":"
	suffix := if windows: ".EXE" else: ""
	root := directory.path()
	blocked := join([root.clone(), "blocked"])
	first := join([root.clone(), "first"])
	second := join([root.clone(), "second"])
	create_directory(blocked, false)?
	create_directory(first, false)?
	create_directory(second, false)?
	create_directory(join([blocked.clone(), "probe{suffix}"]), false)?

	expected := join([first.clone(), "probe{suffix}"])
	make_program(expected)?
	make_program(join([second.clone(), "probe{suffix}"]))?
	set_environment(
		"PATH", "{separator}{blocked}{separator}{first}{separator}{second}{separator}"
	)?
	set_environment("PATHEXT", ".EXE;.CMD")?
	expect_equal(which("probe"), expected)?
	expect_equal(which("missing-manuscript-program"), none)?
	expect_equal(which(""), none)?

	mode_path := join([first, "mode{suffix}"])
	write_file(mode_path, "fixture", false).wait()?
	chmod(mode_path, 384)?
	expect_equal(which("mode").is_some(), windows)?
	chmod(mode_path, 493)?
	expect_equal(which("mode"), mode_path)?

test "which accepts suffixed names and explicit paths without searching PATH":
	directory := temporary("manuscript-which-path-")?
	_restore := save_search_environment()?
	windows := os() == Os.Windows
	name := if windows: "program.EXE" else: "program.bin"
	path := join([directory.path(), name.clone()])
	make_program(path)?
	set_environment("PATH", directory.path())?
	set_environment("PATHEXT", ".EXE;.CMD")?
	expect_equal(which(name), path)?
	set_environment("PATH", "")?

	forward := path.replace("\\", "/")
	native := if windows: path.replace("/", "\\") else: path.clone()
	expect_equal(which(forward), forward)?
	expect_equal(which(native), native)?

	missing := join([directory.path(), "missing.EXE"])
	expect_equal(which(missing), none)?

test "which honors PATHEXT defaults and skips empty PATH entries":
	directory := temporary("manuscript-which-extensions-")?
	_restore := save_search_environment()?
	windows := os() == Os.Windows
	root := directory.path()
	path_key := if windows: "pAtH" else: "PATH"
	extension_key := if windows: "pAtHeXt" else: "PATHEXT"
	selected_suffix := if windows: ".RUN" else: ""
	selected := join([root.clone(), "selected{selected_suffix}"])
	make_program(selected)?
	make_program(join([root.clone(), "selected.CMD"]))?
	make_program(join([root.clone(), "ignored.EXE"]))?
	set_environment(path_key, root)?
	set_environment(extension_key, ".RUN;.CMD")?
	expect_equal(which("selected"), selected)?
	expect_equal(which(join([root.clone(), "selected"])), selected)?
	expect_equal(which("ignored"), none)?

	default_suffix := if windows: ".CMD" else: ""
	default_path := join([root.clone(), "default{default_suffix}"])
	make_program(default_path)?
	set_environment(extension_key, none)?
	expect_equal(which("default"), default_path)?
	change_directory(root)?
	set_environment(path_key, "")?
	expect_equal(which("default"), none)?

	relative := if windows: ".\\default.CMD" else: "./default"
	expect_equal(which(relative), relative)?
