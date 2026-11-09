import expect_equal, expect_false, expect_true from "@std/test/test.ms"
import (
    OpenMode,
    chmod,
    create_directory,
    create_symlink,
    list,
    move,
    open,
    read_file,
    read_symlink,
    stat,
    temporary,
    write_atomic,
    write_file
) from "@std/os/fs.ms"
import milliseconds from "@std/time.ms"
import which from "@std/os/env.ms"
import os, Os from "@std/os/system.ms"

fn text_of(path: String) String!:
    let data = try read_file(path).wait()
    return ok(data.decode_utf8().get(""))

test "write_atomic replaces contents, keeps mode, and leaves no temporary file":
    let directory = try temporary("manuscript-atomic-")
    let root = directory.path()
    let path = "{root}/config.txt"
    try write_atomic(path, "one").wait()
    try expect_equal(try text_of(path), "one")
    try write_file("{root}/mode.txt", "x", false).wait()
    try chmod("{root}/mode.txt", 384)

    let before = (try stat("{root}/mode.txt")).permissions
    let expected = if os() == Os.Windows: 438 else: 384
    try expect_equal(before, expected)
    try write_atomic("{root}/mode.txt", "y").wait()
    try expect_equal((try stat("{root}/mode.txt")).permissions, before)
    try expect_equal(try text_of("{root}/mode.txt"), "y")
    try chmod("{root}/mode.txt", 438)

    let writable = (try stat("{root}/mode.txt")).permissions
    try expect_equal(writable, 438)
    try write_atomic("{root}/mode.txt", "z").wait()
    try expect_equal((try stat("{root}/mode.txt")).permissions, writable)
    try expect_equal(try text_of("{root}/mode.txt"), "z")
    try write_atomic(path, "two".to_bytes()).wait()
    try expect_equal(try text_of(path), "two")

    let names = (try list(root, none)).map(fn e: e.name)
    try expect_equal(names.length(), 2)

test "write_atomic writes through a symbolic link and keeps the link":
    let directory = try temporary("manuscript-atomic-link-")
    let root = directory.path()
    try write_file("{root}/real.txt", "old", false).wait()
    try create_symlink("{root}/link.txt", "real.txt")
    try write_atomic("{root}/link.txt", "new").wait()
    try expect_true((try stat("{root}/link.txt", follow_links: false)).is_symlink())
    try expect_equal(try read_symlink("{root}/link.txt"), "real.txt")
    try expect_equal(try text_of("{root}/real.txt"), "new")
    try expect_equal(try text_of("{root}/link.txt"), "new")
    try expect_equal((try list(root, none)).length(), 2)

test "write_atomic replaces a link that names nothing":
    let directory = try temporary("manuscript-atomic-dangling-")
    let root = directory.path()
    try create_symlink("{root}/dangling.txt", "missing.txt")
    try write_atomic("{root}/dangling.txt", "made").wait()
    try expect_false(
        (try stat("{root}/dangling.txt", follow_links: false)).is_symlink()
    )
    try expect_equal(try text_of("{root}/dangling.txt"), "made")

test "write_atomic fails without touching the target when the directory is missing":
    let directory = try temporary("manuscript-atomic-")
    let outcome = write_atomic("{directory.path()}/missing/file.txt", "x").wait()
    try expect_true(outcome.is_error())

test "advisory locks exclude other handles until unlocked or closed":
    let directory = try temporary("manuscript-lock-")
    let path = "{directory.path()}/lock"
    try write_file(path, "", false).wait()

    var first = try open(path, OpenMode.Read)
    var second = try open(path, OpenMode.Read)
    try expect_true(try first.try_lock(true))
    try expect_false(try second.try_lock(true))
    try expect_false(try second.try_lock(false))
    try expect_false(try second.lock(true, milliseconds(20)))
    try first.unlock()
    try expect_true(try second.try_lock(false))

    var third = try open(path, OpenMode.Read)
    try expect_true(try third.try_lock(false))
    try expect_false(try third.try_lock(true))
    try second.close()
    try third.unlock()
    try expect_true(try third.try_lock(true))

test "move renames files and trees":
    let directory = try temporary("manuscript-move-")
    let root = directory.path()
    try create_directory("{root}/tree/sub", true)
    try write_file("{root}/tree/sub/a.txt", "a", false).wait()
    try move("{root}/tree", "{root}/moved")
    try expect_equal(try text_of("{root}/moved/sub/a.txt"), "a")
    try expect_true(stat("{root}/tree", follow_links: false).is_error())
    try write_file("{root}/f.txt", "f", false).wait()
    try move("{root}/f.txt", "{root}/g.txt")
    try expect_equal(try text_of("{root}/g.txt"), "f")
    try expect_true(move("{root}/missing", "{root}/other").is_error())

test "which finds executables on PATH and rejects missing names":
    try expect_true(which("definitely-not-a-command-xyz").is_none())
    try expect_true(which("").is_none())
    try expect_true(which("sh").is_some() or which("cmd").is_some())

test "write_atomic replaces a file whose name is near the name length limit":
    let directory = try temporary("manuscript-atomic-long-")
    let root = directory.path()
    let name = try "ñ".repeat(120)
    let path = "{root}/{name}"
    try write_atomic(path, "one").wait()
    try write_atomic(path, "two").wait()
    try expect_equal(try text_of(path), "two")

    let names = (try list(root, none)).map(fn e: e.name)
    try expect_equal(names.length(), 1)
