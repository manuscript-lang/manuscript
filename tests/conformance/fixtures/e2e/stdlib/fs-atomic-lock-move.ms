// conform: tags=testing,tier-io
// conform: phase=test
import (
	which from "@std/os/env.ms",
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
	write_file from "@std/os/fs.ms",
	Os, os from "@std/os/system.ms",
	expect_equal, expect_false, expect_true from "@std/test/test.ms",
	milliseconds from "@std/time.ms",
)

fn text_of(path: String) String!:
	data := read_file(path).wait()?
	return ok(data.decode_utf8() or "")

test "write_atomic replaces contents, keeps mode, and leaves no temporary file":
	directory := temporary("manuscript-atomic-")?
	root := directory.path()
	path := f"{root}/config.txt"
	write_atomic(path, "one").wait()?
	expect_equal(text_of(path)?, "one")?
	write_file(f"{root}/mode.txt", "x", false).wait()?
	chmod(f"{root}/mode.txt", 384)?

	before := (stat(f"{root}/mode.txt")?).permissions
	expected := if os() == Os.Windows: 438 else: 384
	expect_equal(before, expected)?
	write_atomic(f"{root}/mode.txt", "y").wait()?
	expect_equal((stat(f"{root}/mode.txt")?).permissions, before)?
	expect_equal(text_of(f"{root}/mode.txt")?, "y")?
	chmod(f"{root}/mode.txt", 438)?

	writable := (stat(f"{root}/mode.txt")?).permissions
	expect_equal(writable, 438)?
	write_atomic(f"{root}/mode.txt", "z").wait()?
	expect_equal((stat(f"{root}/mode.txt")?).permissions, writable)?
	expect_equal(text_of(f"{root}/mode.txt")?, "z")?
	write_atomic(path, "two".to_bytes()).wait()?
	expect_equal(text_of(path)?, "two")?

	names := (list(root, null)?).map(fn e: e.name)
	expect_equal(names.length(), 2)?

test "write_atomic writes through a symbolic link and keeps the link":
	directory := temporary("manuscript-atomic-link-")?
	root := directory.path()
	write_file(f"{root}/real.txt", "old", false).wait()?
	create_symlink(f"{root}/link.txt", "real.txt")?
	write_atomic(f"{root}/link.txt", "new").wait()?
	expect_true((stat(f"{root}/link.txt", follow_links: false)?).is_symlink())?
	expect_equal(read_symlink(f"{root}/link.txt")?, "real.txt")?
	expect_equal(text_of(f"{root}/real.txt")?, "new")?
	expect_equal(text_of(f"{root}/link.txt")?, "new")?
	expect_equal((list(root, null)?).length(), 2)?

test "write_atomic replaces a link that names nothing":
	directory := temporary("manuscript-atomic-dangling-")?
	root := directory.path()
	create_symlink(f"{root}/dangling.txt", "missing.txt")?
	write_atomic(f"{root}/dangling.txt", "made").wait()?
	expect_false((stat(f"{root}/dangling.txt", follow_links: false)?).is_symlink())?
	expect_equal(text_of(f"{root}/dangling.txt")?, "made")?

test "write_atomic fails without touching the target when the directory is missing":
	directory := temporary("manuscript-atomic-")?
	outcome := write_atomic(f"{directory.path()}/missing/file.txt", "x").wait()
	expect_true(outcome.is_error())?

test "advisory locks exclude other handles until unlocked or closed":
	directory := temporary("manuscript-lock-")?
	path := f"{directory.path()}/lock"
	write_file(path, "", false).wait()?

	var first = open(path, OpenMode.Read)?
	var second = open(path, OpenMode.Read)?
	expect_true(first.try_lock(true)?)?
	expect_false(second.try_lock(true)?)?
	expect_false(second.try_lock(false)?)?
	expect_false(second.lock(true, milliseconds(20))?)?
	first.unlock()?
	expect_true(second.try_lock(false)?)?

	var third = open(path, OpenMode.Read)?
	expect_true(third.try_lock(false)?)?
	expect_false(third.try_lock(true)?)?
	second.close()?
	third.unlock()?
	expect_true(third.try_lock(true)?)?

test "move renames files and trees":
	directory := temporary("manuscript-move-")?
	root := directory.path()
	create_directory(f"{root}/tree/sub", true)?
	write_file(f"{root}/tree/sub/a.txt", "a", false).wait()?
	move(f"{root}/tree", f"{root}/moved")?
	expect_equal(text_of(f"{root}/moved/sub/a.txt")?, "a")?
	expect_true(stat(f"{root}/tree", follow_links: false).is_error())?
	write_file(f"{root}/f.txt", "f", false).wait()?
	move(f"{root}/f.txt", f"{root}/g.txt")?
	expect_equal(text_of(f"{root}/g.txt")?, "f")?
	expect_true(move(f"{root}/missing", f"{root}/other").is_error())?

test "which finds executables on PATH and rejects missing names":
	expect_true(which("definitely-not-a-command-xyz") == null)?
	expect_true(which("") == null)?
	expect_true((which("sh") != null) or (which("cmd") != null))?

test "write_atomic replaces a file whose name is near the name length limit":
	directory := temporary("manuscript-atomic-long-")?
	root := directory.path()
	name := "ñ".repeat(120)
	path := f"{root}/{name}"
	write_atomic(path, "one").wait()?
	write_atomic(path, "two").wait()?
	expect_equal(text_of(path)?, "two")?

	names := (list(root, null)?).map(fn e: e.name)
	expect_equal(names.length(), 1)?
