import expect_equal, expect_false, expect_ok, expect_true from "@std/test/test.ms"
import (
    chmod,
    create_directory,
    list,
    move,
    open,
    read_file,
    stat,
    temporary,
    write_atomic,
    write_atomic_bytes,
    write_file
) from "@std/os/fs.ms"
import milliseconds from "@std/os/time.ms"
import which from "@std/os/process.ms"

fn text_of(path: String) String!:
    let data = try read_file(path)
    return ok(data.decode_utf8().get(""))

test "write_atomic replaces contents, keeps mode, and leaves no temporary file":
    let directory = try temporary("manuscript-atomic-")
    let root = directory.path()
    let path = "{root}/config.txt"
    try write_atomic(path, "one")
    try expect_equal(try text_of(path), "one")
    try write_file("{root}/mode.txt", "x", false)
    try chmod("{root}/mode.txt", 384)
    try write_atomic("{root}/mode.txt", "y")
    try expect_equal((try stat("{root}/mode.txt", true)).permissions, 384)
    try write_atomic_bytes(path, "two".to_bytes())
    try expect_equal(try text_of(path), "two")

    let names = (try list(root, none)).map(fn e: e.name)
    try expect_equal(names.length(), 2)

test "write_atomic fails without touching the target when the directory is missing":
    let directory = try temporary("manuscript-atomic-")
    let outcome = write_atomic("{directory.path()}/missing/file.txt", "x")
    try expect_true(outcome.is_error())

test "advisory locks exclude other handles until unlocked or closed":
    let directory = try temporary("manuscript-lock-")
    let path = "{directory.path()}/lock"
    try write_file(path, "", false)

    var first = try open(path, "r", 0)
    var second = try open(path, "r", 0)
    try expect_true(try first.try_lock(true))
    try expect_false(try second.try_lock(true))
    try expect_false(try second.try_lock(false))
    try expect_false(try second.lock(true, milliseconds(20)))
    try first.unlock()
    try expect_true(try second.try_lock(false))

    var third = try open(path, "r", 0)
    try expect_true(try third.try_lock(false))
    try expect_false(try third.try_lock(true))
    try second.close()
    try third.unlock()
    try expect_true(try third.try_lock(true))

test "move renames files and trees":
    let directory = try temporary("manuscript-move-")
    let root = directory.path()
    try create_directory("{root}/tree/sub", true)
    try write_file("{root}/tree/sub/a.txt", "a", false)
    try move("{root}/tree", "{root}/moved")
    try expect_equal(try text_of("{root}/moved/sub/a.txt"), "a")
    try expect_true(stat("{root}/tree", false).is_error())
    try write_file("{root}/f.txt", "f", false)
    try move("{root}/f.txt", "{root}/g.txt")
    try expect_equal(try text_of("{root}/g.txt"), "f")
    try expect_true(move("{root}/missing", "{root}/other").is_error())

test "which finds executables on PATH and rejects missing names":
    try expect_true(which("definitely-not-a-command-xyz").is_none())
    try expect_true(which("").is_none())
    try expect_true(which("sh").is_some() or which("cmd").is_some())
