import Closeable from "@std/core.ms"
import chmod, create_directory, temporary, write_file from "@std/os/fs.ms"
import join from "@std/os/path.ms"
import (
    change_directory,
    environment,
    set_environment,
    which,
    working_directory
) from "@std/os/env.ms"
import (os, Os) from "@std/os/system.ms"
import expect_equal from "@std/test/test.ms"

type SearchEnvironment:
    path: String?
    extensions: String?
    directory: String

impl Closeable for SearchEnvironment:
    var fn close() Unit!:
        try set_environment("PATH", self.path.clone())
        try set_environment("PATHEXT", self.extensions.clone())
        try change_directory(self.directory)
        return ok(unit)

fn saved_variable(values: Map[String, String], name: String) String?:
    let windows = os() == Os.Windows

    for entry in values.entries():
        let key = if windows: entry.key.upper() else: entry.key
        if key == name: return entry.value.clone()

    return none

fn save_search_environment() SearchEnvironment!:
    let values = try environment()
    return ok(
        SearchEnvironment(
            saved_variable(values, "PATH"), saved_variable(values, "PATHEXT"),
            try working_directory()
        )
    )

fn make_program(path: String) Unit!:
    try write_file(path, "#!/bin/sh\nexit 0\n", false).wait()
    try chmod(path, 493)
    return ok(unit)

test "which preserves PATH order and rejects directories and nonexecutable files":
    let directory = try temporary("manuscript-which-order-")
    let _restore = try save_search_environment()
    let windows = os() == Os.Windows
    let separator = if windows: ";" else: ":"
    let suffix = if windows: ".EXE" else: ""
    let root = directory.path()
    let blocked = join([root.clone(), "blocked"])
    let first = join([root.clone(), "first"])
    let second = join([root.clone(), "second"])
    try create_directory(blocked, false)
    try create_directory(first, false)
    try create_directory(second, false)
    try create_directory(join([blocked.clone(), "probe{suffix}"]), false)

    let expected = join([first.clone(), "probe{suffix}"])
    try make_program(expected)
    try make_program(join([second.clone(), "probe{suffix}"]))
    try set_environment(
        "PATH", "{separator}{blocked}{separator}{first}{separator}{second}{separator}"
    )
    try set_environment("PATHEXT", ".EXE;.CMD")
    try expect_equal(which("probe"), expected)
    try expect_equal(which("missing-manuscript-program"), none)
    try expect_equal(which(""), none)

    let mode_path = join([first, "mode{suffix}"])
    try write_file(mode_path, "fixture", false).wait()
    try chmod(mode_path, 384)
    try expect_equal(which("mode").is_some(), windows)
    try chmod(mode_path, 493)
    try expect_equal(which("mode"), mode_path)

test "which accepts suffixed names and explicit paths without searching PATH":
    let directory = try temporary("manuscript-which-path-")
    let _restore = try save_search_environment()
    let windows = os() == Os.Windows
    let name = if windows: "program.EXE" else: "program.bin"
    let path = join([directory.path(), name.clone()])
    try make_program(path)
    try set_environment("PATH", directory.path())
    try set_environment("PATHEXT", ".EXE;.CMD")
    try expect_equal(which(name), path)
    try set_environment("PATH", "")

    let forward = path.replace("\\", "/")
    let native = if windows: path.replace("/", "\\") else: path.clone()
    try expect_equal(which(forward), forward)
    try expect_equal(which(native), native)

    let missing = join([directory.path(), "missing.EXE"])
    try expect_equal(which(missing), none)

test "which honors PATHEXT defaults and skips empty PATH entries":
    let directory = try temporary("manuscript-which-extensions-")
    let _restore = try save_search_environment()
    let windows = os() == Os.Windows
    let root = directory.path()
    let path_key = if windows: "pAtH" else: "PATH"
    let extension_key = if windows: "pAtHeXt" else: "PATHEXT"
    let selected_suffix = if windows: ".RUN" else: ""
    let selected = join([root.clone(), "selected{selected_suffix}"])
    try make_program(selected)
    try make_program(join([root.clone(), "selected.CMD"]))
    try make_program(join([root.clone(), "ignored.EXE"]))
    try set_environment(path_key, root)
    try set_environment(extension_key, ".RUN;.CMD")
    try expect_equal(which("selected"), selected)
    try expect_equal(which(join([root.clone(), "selected"])), selected)
    try expect_equal(which("ignored"), none)

    let default_suffix = if windows: ".CMD" else: ""
    let default_path = join([root.clone(), "default{default_suffix}"])
    try make_program(default_path)
    try set_environment(extension_key, none)
    try expect_equal(which("default"), default_path)
    try change_directory(root)
    try set_environment(path_key, "")
    try expect_equal(which("default"), none)

    let relative = if windows: ".\\default.CMD" else: "./default"
    try expect_equal(which(relative), relative)
